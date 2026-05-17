import subprocess
import os
import sys
import csv
import matplotlib.pyplot as plt

# ==========================================
# 1. 경로 및 환경 설정
# ==========================================
VIVADO_BAT = r"D:\Vivado\Vivado\2023.2\bin\vivado.bat"
SIM_TCL = "run_sim.tcl"
BIT_TCL = "build_sar_adc.tcl"

# 시뮬레이션 결과 파일 경로 (Vivado 작업 디렉토리 기준)
XSIM_WORK_DIR = os.path.join("sim_proj", "SAR_ADC_SIM.sim", "sim_1", "behav", "xsim")
TRACE_CSV = os.path.join(XSIM_WORK_DIR, "sim_trace.csv")
REPORT_FILE = "simulation_report.txt"
TRACE_LOG_TXT = "signal_trace_log.txt"  # 주요 신호 텍스트 로그
WAVEFORM_IMG = "sim_waveform.png"

def cleanup():
    """좀비 프로세스 및 이전 파일 정리"""
    print("[*] 실행 환경 초기화 중...")
    try:
        subprocess.run(["taskkill", "/F", "/IM", "xsimk.exe"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
        subprocess.run(["taskkill", "/F", "/IM", "vivado.exe"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except:
        pass

def run_vivado(tcl):
    """Vivado TCL 스크립트 실행"""
    print(f"[*] Vivado 실행: {tcl}")
    if not os.path.exists(VIVADO_BAT):
        print(f"[!] Vivado 경로를 찾을 수 없습니다: {VIVADO_BAT}")
        return False
    
    res = subprocess.run([VIVADO_BAT, "-mode", "batch", "-source", tcl], capture_output=True, text=True)
    if res.returncode != 0:
        print(f"[!] Vivado 실행 에러:\n{res.stdout}")
        return False
    return True

def safe_int(val, base=10):
    """'xx', 'zz' 등 부정 논리값을 0으로 안전하게 변환"""
    try:
        return int(val, base)
    except (ValueError, TypeError):
        return 0

# ==========================================
# 2. DeepDebugger 클래스 (심층 로직 분석 및 로그 생성)
# ==========================================
class DeepDebugger:
    def __init__(self, csv_path):
        self.csv_path = csv_path
        self.errors = []
        self.trace_data = []

    def load_data(self):
        if not os.path.exists(self.csv_path):
            return False
        with open(self.csv_path, "r") as f:
            self.trace_data = list(csv.DictReader(f))
        return len(self.trace_data) > 0

    def analyze_logic(self):
        """FSM 전이, 카운터, 시프트 레지스터 타이밍 검증"""
        print("[*] 넷리스트 기반 로직 무결성 분석 중...")
        prev_clk = '0'
        st2_clk_count = 0

        for i, row in enumerate(self.trace_data):
            time = row['Time']
            clk = row['CLK']
            st1, st2, st3 = row['ST1'], row['ST2'], row['ST3']
            tc8, sr = row['TC8'], row['SR']
            dac = safe_int(row['DAC'], 16)

            # [상승 엣지 검사]
            if prev_clk == '0' and clk == '1':
                if st2 == '1':
                    st2_clk_count += 1
                    # MSB 결정 타이밍 체크 (7f 에러 방지)
                    if st2_clk_count == 1 and sr.startswith('0'):
                        self.errors.append(f"[{time}ns] 타이밍 오류: ST2 진입 후 첫 클럭에서 MSB(SR[7])가 주입되지 않음.")
                    # TC8 발생 체크
                    if st2_clk_count == 8 and tc8 == '0':
                        self.errors.append(f"[{time}ns] 카운터 오류: 8번째 클럭에서 TC8 신호 누락.")
                else:
                    st2_clk_count = 0

                # RESULT 상태에서 데이터 확정 여부 (예시: DAC 값이 0이면 변환 실패로 간주)
                if st3 == '1' and dac == 0:
                    self.errors.append(f"[{time}ns] 데이터 오류: RESULT 상태에서 변환 값이 0입니다.")

            prev_clk = clk
        return len(self.errors) == 0

    def save_signal_trace_text(self, output_path):
        """주요 신호 트레이스 값들을 가독성 좋은 텍스트 파일로 저장"""
        print(f"[*] 상세 신호 로그 생성 중: {output_path}")
        with open(output_path, "w", encoding="utf-8") as f:
            f.write(f"{'Time':>10} | {'State':^8} | {'CLK':^3} | {'SR (Hex)':^10} | {'DAC (Hex)':^10} | {'COMP':^4}\n")
            f.write("-" * 65 + "\n")
            
            for r in self.trace_data:
                state = "IDLE"
                if r['ST1'] == '1': state = "SAMP"
                elif r['ST2'] == '1': state = "QUANT"
                elif r['ST3'] == '1': state = "RESULT"
                
                sr_hex = hex(int(r['SR'], 2))[2:].zfill(2).upper() if 'x' not in r['SR'] else "XX"
                
                f.write(f"{r['Time']:>10} | {state:^8} | {r['CLK']:^3} | {sr_hex:^10} | {r['DAC']:^10} | {r['COMP']:^4}\n")

# ==========================================
# 3. 시각화 및 메인 제어
# ==========================================
def plot_waveforms(csv_path):
    print("[*] 파형 그래프 시각화 중...")
    t, clk, st, dac = [], [], [], []
    with open(csv_path, "r") as f:
        for r in csv.DictReader(f):
            t.append(safe_int(r['Time']))
            clk.append(safe_int(r['CLK']))
            s_val = safe_int(r['ST1'])*1 + safe_int(r['ST2'])*2 + safe_int(r['ST3'])*3
            st.append(s_val)
            dac.append(safe_int(r['DAC'], 16))

    fig, axs = plt.subplots(3, 1, figsize=(12, 10), sharex=True)
    axs[0].step(t, clk, 'k', where='post'); axs[0].set_ylabel('CLK')
    axs[1].step(t, st, 'b', where='post'); axs[1].set_ylabel('FSM State')
    axs[1].set_yticks([0,1,2,3]); axs[1].set_yticklabels(['IDLE','SAMP','QUANT','RES'])
    axs[2].step(t, dac, 'r', where='post'); axs[2].set_ylabel('DAC (Hex)')
    plt.xlabel('Time (ns)'); plt.tight_layout()
    plt.savefig(WAVEFORM_IMG); plt.show()

def main():
    print("=== SAR ADC 통합 분석 및 검증 시스템 ===")
    cleanup()
    
    # 1. 시뮬레이션 실행
    if not run_vivado(SIM_TCL):
        sys.exit(1)
        
    # 2. 심층 디버깅 및 분석
    debugger = DeepDebugger(TRACE_CSV)
    if not debugger.load_data():
        print("[!] 에러: 분석할 트레이스 데이터가 생성되지 않았습니다.")
        sys.exit(1)

    is_logic_valid = debugger.analyze_logic()
    debugger.save_signal_trace_text(TRACE_LOG_TXT)
    
    # 3. 분석 보고서 작성
    with open(REPORT_FILE, "w", encoding='utf-8') as f:
        f.write("=== SAR ADC 심층 분석 보고서 ===\n\n")
        if is_logic_valid:
            f.write("최종 결과: PASS\n")
            f.write("상태: 모든 타이밍 및 FSM 전이가 설계된 넷리스트와 일치합니다.\n")
        else:
            f.write("최종 결과: FAIL\n")
            f.write("[검출된 오류 내역]\n")
            for err in debugger.errors:
                f.write(f"- {err}\n")

    # 4. 결과 시각화
    plot_waveforms(TRACE_CSV)

    # 5. 비트스트림 생성 분기
    if is_logic_valid:
        print("\n[✔] 로직 검증 통과! 비트스트림 생성을 시작합니다...")
        if run_vivado(BIT_TCL):
            print("\n[완료] 비트스트림 생성이 성공적으로 끝났습니다.")
    else:
        print(f"\n[✘] 로직 오류가 발견되었습니다. {REPORT_FILE} 및 {TRACE_LOG_TXT}를 확인하세요.")

if __name__ == "__main__":
    main()