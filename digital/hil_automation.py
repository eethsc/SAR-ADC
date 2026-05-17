import subprocess
import os
import matplotlib.pyplot as plt

VIVADO_BAT = r"D:\Vivado\Vivado\2023.2\bin\vivado.bat"
TCL_SCRIPT = "hw_test_control.tcl"
STIMULUS_FILE = "stimulus.txt"
RESULTS_FILE = "hw_results.txt"

def generate_stimulus():
    """테스트 시나리오 생성 (예: 비교기 신호의 연속 주입 패턴)"""
    print("[*] 테스트 시나리오 생성 중...")
    with open(STIMULUS_FILE, "w") as f:
        # 다양한 비교기 응답 시나리오를 작성 (0 또는 1)
        # 실제로는 SAR 로직 특성상 복잡한 시퀀스가 필요할 수 있음
        test_cases = ["1", "0", "1", "1", "0", "0", "1", "0"]
        for case in test_cases:
            f.write(f"{case}\n")

def run_hardware_test():
    """Vivado를 배치 모드로 실행하여 실제 보드 테스트 수행"""
    print("[*] Vivado Hardware Manager 접속 및 HIL 테스트 시작...")
    if not os.path.exists(VIVADO_BAT):
        print("[!] Vivado 경로가 잘못되었습니다.")
        return False
    
    cmd = [VIVADO_BAT, "-mode", "batch", "-source", TCL_SCRIPT]
    result = subprocess.run(cmd, capture_output=True, text=True, encoding='cp949', errors='ignore')
    
    if result.returncode == 0:
        print("[✔] 하드웨어 테스트 완료.")
        return True
    else:
        print(f"[✘] 테스트 실패:\n{result.stdout}")
        return False

def analyze_results():
    """결과 데이터를 읽어 성공 여부 판별 및 시각화"""
    print("[*] 결과 분석 및 그래프 생성 중...")
    inputs, outputs = [], []
    with open(RESULTS_FILE, "r") as f:
        next(f) # 헤더 건너뛰기
        for line in f:
            comp, dac = line.strip().split(',')
            inputs.append(int(comp))
            outputs.append(int(dac, 16))

    plt.figure(figsize=(10, 5))
    plt.plot(outputs, 'bo-', label='Measured DAC Value')
    plt.title('SAR ADC Hardware Loopback Test Results')
    plt.xlabel('Test Case Index')
    plt.ylabel('DAC Output (Dec)')
    plt.grid(True)
    plt.savefig("hw_test_plot.png")
    plt.show()

if __name__ == "__main__":
    generate_stimulus()
    if run_hardware_test():
        analyze_results()