import subprocess
import os
import sys
import csv
import matplotlib.pyplot as plt

WORKING_DIR = os.path.dirname(os.path.abspath(__file__))
VIVADO_BAT = r"D:\Vivado\Vivado\2023.2\bin\vivado.bat"
TCL_SCRIPT = os.path.join(WORKING_DIR, "hw_test_control.tcl")

HW_TRACE_CSV = os.path.join(WORKING_DIR, "hardware_live_trace.csv")
RESULTS_PLOT = os.path.join(WORKING_DIR, "live_sine_wave_plot.png")

def run_infinite_hil_stream():
    print("=========================================================")
    print("[*] 1kHz 조건 맞춤형 데이터 래치 & 고속 VIO 스트리밍 시스템")
    print(f"[*] 데이터 기록 파일: {HW_TRACE_CSV}")
    print("[*] 수집을 종료하고 결과 그래프를 보려면 'Ctrl + C'를 누르세요.")
    print("=========================================================")
    
    if not os.path.exists(VIVADO_BAT):
        print(f"[!] 에러: Vivado 경로가 올바르지 않습니다.\n입력된 경로: {VIVADO_BAT}")
        return

    if not os.path.exists(TCL_SCRIPT):
        print(f"[!] 에러: 매핑할 TCL 스크립트 파일이 없습니다.\n확인된 경로: {TCL_SCRIPT}")
        return

    process = subprocess.Popen(
        [VIVADO_BAT, "-mode", "batch", "-source", TCL_SCRIPT], 
        stdout=subprocess.PIPE, 
        stderr=subprocess.STDOUT, 
        text=True, 
        encoding='cp949', 
        errors='ignore'
    )

    adc_raw_data = []
    st1_data = []
    st3_data = []
    
    print("[*] Vivado Hardware Manager 하드웨어 세션 초기화 중... 잠시만 기다려주세요.")

    csv_f = open(HW_TRACE_CSV, "w", newline="", encoding="utf-8")
    csv_writer = csv.writer(csv_f)
    csv_writer.writerow(["Sample_Index", "DAC_Dec", "ST1_SAMP", "ST3_RESULT"])
    csv_f.flush()

    sample_cnt = 0
    last_saved_val = None  # 중복 기록 방지용 버퍼

    try:
        for line in process.stdout:
            clean_line = line.strip()
            
            if "TCL_STATUS:" in clean_line:
                print(f"\n  [Vivado] {clean_line}")
                continue
            
            if "STREAM_DATA:" in clean_line:
                try:
                    parts = clean_line.split("STREAM_DATA:")
                    tokens = parts[1].strip().split(",")
                    
                    hex_val = tokens[0].replace("0x", "")
                    dec_val = int(hex_val, 16)
                    
                    val_st1 = int(tokens[1], 16) if len(tokens) > 1 else 0
                    val_st3 = int(tokens[2], 16) if len(tokens) > 2 else 0
                    
                    # =========================================================
                    # 💡 [핵심 알고리즘 수정] 1kHz 클럭 데이터 필터링 조건문
                    # 변환이 끝난 RESULT(ST3) 상태가 HIGH인 깨끗한 데이터만 타깃 래치
                    # =========================================================
                    if val_st3 == 1:
                        # 동일한 변환 사이클 내 중복 수집 필터링
                        if dec_val != last_saved_val:
                            adc_raw_data.append(dec_val)
                            st1_data.append(val_st1)
                            st3_data.append(val_st3)
                            
                            csv_writer.writerow([sample_cnt, dec_val, val_st1, val_st3])
                            csv_f.flush()
                            
                            sample_cnt += 1
                            last_saved_val = dec_val
                            
                            fsm_status_str = f"DAC_VALID: {dec_val} (0x{hex_val.upper()}) | ST1: {val_st1} | ST3: {val_st3}"
                            print(f"\r[안정적 수집 및 저장 중] 총 유효 샘플 수: {sample_cnt}개 | {fsm_status_str}", end="")
                    
                    # 장시간 구동 시 메모리 윈도우 스케일 가드
                    if len(adc_raw_data) > 1500:
                        adc_raw_data.pop(0)
                        st1_data.pop(0)
                        st3_data.pop(0)
                        
                except (ValueError, IndexError):
                    pass
            
            elif "ERROR:" in clean_line and not clean_line.startswith("#"):
                print(f"\n[!] Vivado 하드웨어 통신 에러 발생: {clean_line}")

    except KeyboardInterrupt:
        print("\n\n[*] 사용자가 종료 신호(Ctrl+C)를 입력했습니다.")
        print("[*] 하드웨어 커넥션을 안전하게 해제하고 결과 분석 파형을 생성합니다...")
        
    finally:
        csv_f.close()
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()

    if adc_raw_data:
        print(f"\n[*] 총 {len(adc_raw_data)}개의 정제된 데이터로 복원 그래프 플로팅 중...")
        
        fig, axs = plt.subplots(3, 1, figsize=(12, 10), sharex=True)
        
        # Subplot 1: 필터링되어 안정화된 가상 정현파 출력
        axs[0].plot(adc_raw_data, 'g-', linewidth=2, label='Filtered Valid Sine Wave')
        axs[0].plot(adc_raw_data, 'ro', markersize=3, alpha=0.5, label='ADC Fixed Points')
        axs[0].set_title('SAR ADC 1kHz Hardware Synchronized Stream Test (Filtered)', fontsize=14)
        axs[0].set_ylabel('8-Bit Valid Code (Dec)')
        axs[0].set_ylim(-10, 265)
        axs[0].grid(True, linestyle=':')
        axs[0].legend(loc='upper right')
        
        axs[1].step(range(len(st1_data)), st1_data, 'b-', where='post', label='ST1 (Sampling)')
        axs[1].set_ylabel('ST1 Status')
        axs[1].set_ylim(-0.2, 1.2)
        axs[1].grid(True, linestyle=':')
        
        axs[2].step(range(len(st3_data)), st3_data, 'm-', where='post', label='ST3 (Result Valid)')
        axs[2].set_ylabel('ST3 Status')
        axs[2].set_ylim(-0.2, 1.2)
        axs[2].grid(True, linestyle=':')
        
        plt.xlabel('Sample Window Index (Valid Commits)', fontsize=12)
        plt.tight_layout()
        
        plt.savefig(RESULTS_PLOT)
        print(f"[✔] 그래프 이미지 저장 완료: {RESULTS_PLOT}")
        print(f"[✔] 정제된 전체 이력 CSV 저장 완료: {HW_TRACE_CSV}")
        plt.show()
    else:
        print("\n[!] 필터링 조건(ST3 == 1)을 만족하는 유효 데이터가 수집되지 않았습니다.")
        print("    팁: 앞서 조치한 sar_adc_top.v 내의 u_vio에 st1, st3 핀 와이어 연결이 완료되었는지 꼭 확인하세요.")

if __name__ == "__main__":
    run_infinite_hil_stream()