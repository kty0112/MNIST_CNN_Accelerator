#!/bin/bash
##########################################################################
## Zybo-Z7-Pcam-MNIST-CNN Setup Script
## Pcam 프로젝트 다운로드 -> CNN IP 패키징 -> Block Design 통합 -> 빌드
##
## 사전 조건:
##   - Vivado 2023.2 설치 (PATH에 vivado 포함)
##   - Vitis 2023.2 설치 (PATH에 xsct 포함)
##   - GitHub CLI (gh) 로그인 완료
##
## 사용법:
##   chmod +x scripts/setup.sh
##   ./scripts/setup.sh /path/to/vivado /path/to/vitis
##########################################################################

set -e

VIVADO_BIN="${1:-vivado}"
XSCT_BIN="${2:-xsct}"
REPO_DIR="$(cd "$(dirname "$0")/.." && pwd)"
WORK_DIR="$REPO_DIR/build"

echo "============================================="
echo "  Zybo-Z7-Pcam-MNIST-CNN Setup"
echo "  Repo: $REPO_DIR"
echo "  Work: $WORK_DIR"
echo "============================================="

# 1. Download Pcam 2023.1 project
echo ""
echo "[1/5] Downloading Pcam-5C project..."
mkdir -p "$WORK_DIR/pcam_download"
gh release download "20/Pcam-5C/2023.1-1" --repo Digilent/Zybo-Z7 --dir "$WORK_DIR/pcam_download"
cd "$WORK_DIR/pcam_download"
unzip -qo Zybo-Z7-20-Pcam-5C-hw.xpr.zip
unzip -qo Zybo-Z7-20-Pcam-5C-sw.ide.zip
echo "  Done."

# 2. Package CNN IP
echo ""
echo "[2/5] Packaging CNN IP..."
mkdir -p "$WORK_DIR/ip_repo/cnn_mnist_ip/src"
cp "$REPO_DIR/src/"*.vhd "$WORK_DIR/ip_repo/cnn_mnist_ip/src/"

# Update package_ip.tcl paths
sed -e "s|set ip_dir.*|set ip_dir \"$WORK_DIR/ip_repo/cnn_mnist_ip\"|" \
    -e "s|set proj_dir.*|set proj_dir \"$WORK_DIR/ip_repo/package_project\"|" \
    "$REPO_DIR/scripts/package_ip.tcl" > "$WORK_DIR/package_ip_local.tcl"

$VIVADO_BIN -mode batch -source "$WORK_DIR/package_ip_local.tcl"
echo "  Done."

# 3. Integrate CNN into Pcam Block Design
echo ""
echo "[3/5] Integrating CNN into Pcam Block Design..."
sed -e "s|set pcam_source.*|set pcam_source \"$WORK_DIR/pcam_download/hw\"|" \
    -e "s|set new_proj_dir.*|set new_proj_dir \"$WORK_DIR/vivado_project\"|" \
    -e "s|set ip_repo_path.*|set ip_repo_path \"$WORK_DIR/ip_repo/cnn_mnist_ip\"|" \
    "$REPO_DIR/scripts/integrate_cnn.tcl" > "$WORK_DIR/integrate_local.tcl"

$VIVADO_BIN -mode batch -source "$WORK_DIR/integrate_local.tcl"
echo "  Done."

# 4. Generate Bitstream
echo ""
echo "[4/5] Generating Bitstream..."
$VIVADO_BIN -mode batch -source - <<EOF
open_project $WORK_DIR/vivado_project/cnn_pcam.xpr
launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1
write_hw_platform -fixed -force -include_bit -file $WORK_DIR/cnn_pcam.xsa
close_project
EOF
echo "  Done."

# 5. Build Vitis Software
echo ""
echo "[5/5] Building Vitis software..."
mkdir -p "$WORK_DIR/sw_src"
cp -r "$REPO_DIR/sw/src/"* "$WORK_DIR/sw_src/"

sed -e "s|set xsa_file.*|set xsa_file \"$WORK_DIR/cnn_pcam.xsa\"|" \
    -e "s|set ws_dir.*|set ws_dir \"$WORK_DIR/vitis_ws\"|" \
    -e "s|set sw_src.*|set sw_src \"$WORK_DIR/sw_src\"|" \
    "$REPO_DIR/scripts/create_vitis.tcl" > "$WORK_DIR/create_vitis_local.tcl"

$XSCT_BIN "$WORK_DIR/create_vitis_local.tcl"
echo "  Done."

echo ""
echo "============================================="
echo "  BUILD COMPLETE!"
echo ""
echo "  Bitstream: $WORK_DIR/vivado_project/cnn_pcam.runs/impl_1/system_wrapper.bit"
echo "  XSA:       $WORK_DIR/cnn_pcam.xsa"
echo "  ELF:       $WORK_DIR/vitis_ws/cnn_mnist_app/Debug/cnn_mnist_app.elf"
echo "============================================="
