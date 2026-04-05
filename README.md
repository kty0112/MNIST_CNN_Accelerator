# Zybo-Z7-Pcam-MNIST-CNN

Zybo Z7-20 + Pcam-5C 카메라를 사용한 **실시간 MNIST 손글씨 숫자 인식** FPGA 프로젝트.

> **[FPGA CNN 하드웨어 설계 가이드](docs/HARDWARE_DESIGN_GUIDE_KR.md)** — 모든 VHDL 모듈의 동작 원리를 그림과 비유로 설명합니다.

## 시스템 구조

```
Pcam-5C (MIPI 카메라)
    |
    v
[MIPI D-PHY RX] -> [MIPI CSI-2 RX] -> [BayerToRGB] -> [GammaCorrection]
                                                              |
                                                     [AXI Stream Broadcaster]
                                                        |              |
                                                        v              v
                                                     [VDMA]     [CNN MNIST IP]
                                                        |              |
                                                        v              v
                                                   HDMI 출력     AXI-Lite 레지스터
                                                  (원본 영상)         |
                                                                      v
                                                               Zynq PS (ARM)
                                                                      |
                                                                      v
                                                              UART 시리얼 출력
                                                          "Digit: 3 (87%)"
```

## CNN 아키텍처

LeNet-style 3-layer CNN, 28x28 grayscale 입력, 0~9 숫자 분류.

```
Input (28x28x1)
  -> Conv1 (3x3, 4 filters, same, ReLU) -> MaxPool (2x2)
  -> Conv2 (3x3, 6 filters, same, ReLU) -> MaxPool (2x2)
  -> Conv3 (3x3, 8 filters, same, ReLU) -> MaxPool (2x2)
  -> Flatten (3x3x8 = 72)
  -> FC (72 -> 10, ReLU)
  -> Argmax -> Prediction (0~9) + Probability
```

- 가중치: 1,438개 (8-bit 고정소수점, ROM 저장)
- 활성화: ReLU (전 레이어)
- 전처리: RGB -> Grayscale (BT.601) -> 16:1 MaxPool 다운스케일

## FPGA 리소스 사용량 (xc7z020)

| 리소스 | 사용 | 가용 | 사용률 |
|--------|------|------|--------|
| Slice LUTs | 1,832 | 53,200 | 3.44% |
| Registers | 2,486 | 106,400 | 2.34% |
| Block RAM | 3 tiles | 140 tiles | 2.14% |
| DSP48E1 | 4 | 220 | 1.82% |

## 필요 장비

- Zybo Z7-20 (xc7z020clg400-1)
- Pcam-5C (OV5640 MIPI 카메라)
- HDMI 모니터 + 케이블
- Micro-USB 케이블 (JTAG + UART)

## 필요 소프트웨어

- Vivado 2023.2
- Vitis 2023.2
- GitHub CLI (`gh`)

## 빠른 시작 (자동 빌드)

```bash
git clone https://github.com/squid55/Zybo-Z7-Pcam-MNIST-CNN.git
cd Zybo-Z7-Pcam-MNIST-CNN
./scripts/setup.sh /path/to/vivado /path/to/xsct
```

setup.sh가 자동으로:
1. Digilent Pcam 프로젝트 다운로드
2. CNN IP 패키징
3. Block Design에 CNN 통합
4. Bitstream 생성
5. Vitis 소프트웨어 빌드

## 수동 빌드

### Step 1: Pcam 프로젝트 다운로드

```bash
gh release download "20/Pcam-5C/2023.1-1" --repo Digilent/Zybo-Z7 --dir pcam_download
cd pcam_download
unzip Zybo-Z7-20-Pcam-5C-hw.xpr.zip
unzip Zybo-Z7-20-Pcam-5C-sw.ide.zip
```

### Step 2: CNN IP 패키징

```bash
# ip_repo/cnn_mnist_ip/src/ 에 src/*.vhd 복사 후
vivado -mode batch -source scripts/package_ip.tcl
```

### Step 3: Block Design 통합

`scripts/integrate_cnn.tcl`에서 경로 수정 후:

```bash
vivado -mode batch -source scripts/integrate_cnn.tcl
```

이 스크립트가 자동으로:
- Pcam 프로젝트를 새 위치에 복사
- CNN IP 추가
- GammaCorrection -> Broadcaster -> VDMA + CNN 연결
- AXI-Lite 주소 할당
- HDL Wrapper 생성

### Step 4: Bitstream 생성

Vivado GUI에서 프로젝트 열기 -> Generate Bitstream 클릭.
또는:

```bash
vivado -mode batch -source - <<'EOF'
open_project /path/to/cnn_pcam.xpr
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
write_hw_platform -fixed -force -include_bit -file cnn_pcam.xsa
close_project
EOF
```

### Step 5: Vitis 소프트웨어 빌드

`scripts/create_vitis.tcl`에서 경로 수정 후:

```bash
xsct scripts/create_vitis.tcl
```

### Step 6: FPGA에 다운로드

```tcl
# xsct에서 실행
connect
targets -set -filter {name =~ "ARM*#0"}
rst -system
fpga cnn_pcam.bit
source vitis_ws/cnn_pcam_platform/ps7_init.tcl
ps7_init
ps7_post_config
dow vitis_ws/cnn_mnist_app/Debug/cnn_mnist_app.elf
con
```

### Step 7: 결과 확인

시리얼 터미널 (115200 baud) 연결:

```
====================================
  CNN MNIST Real-time Recognition
  Zybo Z7-20 + Pcam-5C
====================================

Video pipeline initialized (720p 60fps).
CNN inference running in hardware...

>> NEW DIGIT DETECTED <<
[000001] Digit: 3  Confidence: 87%  (raw: 891/1023)
```

## 파일 구조

```
Zybo-Z7-Pcam-MNIST-CNN/
  src/                              -- VHDL 설계 소스 (14개)
    image_data_pkg.vhd              -- 이미지 타입 정의
    cnn_config_pkg.vhd              -- CNN 설정, 활성화 함수
    cnn_data_pkg.vhd                -- 학습된 가중치 1,438개
    cnn_row_expander.vhd            -- 행 시간 확장기
    cnn_row_buffer.vhd              -- 컨볼루션 매트릭스 버퍼
    cnn_convolution.vhd             -- 2D 컨볼루션 레이어
    cnn_pooling.vhd                 -- Max Pooling 레이어
    nn_layer.vhd                    -- Fully Connected 레이어
    max_pooling_pre.vhd             -- 전처리 다운스케일 (448->28)
    rgb_to_cnn.vhd                  -- RGB -> CNN 스트림 변환
    cnn_top.vhd                     -- CNN 최상위 모듈
    axi_stream_to_rgb_stream.vhd    -- AXI Stream -> rgb_stream 브릿지
    cnn_result_axilite.vhd          -- CNN 결과 AXI-Lite 레지스터
    cnn_pcam_wrapper.vhd            -- 시스템 래퍼 (브릿지 + CNN + AXI-Lite)
  tb/                               -- 테스트벤치
    cnn_top_tb.vhd                  -- CNN 기능 검증 (숫자 "1" 패턴)
  sw/src/                           -- Vitis C++ 소프트웨어
    main.cc                         -- CNN 결과 폴링 + UART 출력
    ov5640/                         -- Pcam 카메라 드라이버
    hdmi/                           -- HDMI 출력 드라이버
    platform/                       -- Zynq 플랫폼 초기화
  scripts/                          -- 자동화 스크립트
    setup.sh                        -- 전체 빌드 원클릭 스크립트
    package_ip.tcl                  -- CNN IP 패키징
    integrate_cnn.tcl               -- Pcam BD에 CNN 통합
    create_vitis.tcl                -- Vitis 프로젝트 생성
  cnn_schematic.pdf                 -- CNN RTL 회로도
  CNN_VHDL_MODULE_GUIDE.md          -- 모듈별 상세 설명서
  README.md                         -- 이 문서
```

## CNN AXI-Lite 레지스터 맵

| Offset | 이름 | 접근 | 설명 |
|--------|------|------|------|
| 0x00 | Prediction | Read | 인식된 숫자 (0~9) |
| 0x04 | Probability | Read | 신뢰도 (0~1023) |
| 0x08 | Status | Read | bit0 = result valid |

Base Address: Block Design Address Editor에서 자동 할당.

## 원본 출처

- CNN 코어: [OnSemi CNN Ultra](https://github.com/leonbeier/OnSemi_CNN_Ultra) (Leon Beier, VHDP -> VHDL 변환)
- Pcam 데모: [Digilent Zybo-Z7 Pcam-5C](https://github.com/Digilent/Zybo-Z7/releases)

## 라이선스

CNN 코어: MIT License (Leon Beier, Protop Solutions UG)
Pcam 드라이버: Digilent License
