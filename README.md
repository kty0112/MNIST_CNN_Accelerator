# Zybo-Z7-Pcam-MNIST-CNN

Zybo Z7-20 + Pcam-5C 카메라를 사용한 **실시간 MNIST 손글씨 숫자 인식** FPGA 프로젝트.

<img width="1067" height="378" alt="image" src="https://github.com/user-attachments/assets/b593d95d-c116-43f1-aa4e-328d2b88e6e8" />

<img width="2051" height="1851" alt="image" src="https://github.com/user-attachments/assets/438dfa89-fc37-4093-a19e-51d977e20c40" />
Memory Access Minimization in PE Array
<img width="2254" height="1154" alt="image" src="https://github.com/user-attachments/assets/8dfaaca5-fffb-4fb3-a25e-c6f839072004" />
FIFO, MaxPooling, and ReLU Integration
<img width="2079" height="839" alt="image" src="https://github.com/user-attachments/assets/cd2ad958-939b-469f-aea2-e67c06877668" />
Shift Buffer Utilization
<img width="2098" height="425" alt="image" src="https://github.com/user-attachments/assets/e31f8256-2e5c-4b34-9a5e-1ae307467d97" />
Fully Connected (FC) Layer Implementation
<img width="2152" height="709" alt="image" src="https://github.com/user-attachments/assets/e28ede5b-240e-40bd-abb9-3a7b4d060900" />




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



## CNN AXI-Lite 레지스터 맵

| Offset | 이름 | 접근 | 설명 |
|--------|------|------|------|
| 0x00 | Prediction | Read | 인식된 숫자 (0~9) |
| 0x04 | Probability | Read | 신뢰도 (0~1023) |
| 0x08 | Status | Read | bit0 = result valid |

Base Address: Block Design Address Editor에서 자동 할당.


