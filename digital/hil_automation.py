import subprocess
import os
import sys
import matplotlib.pyplot as plt

# [유지] 스크립트 위치 기준 동적 절대 경로 탐색 로직
WORKING_DIR = os.path.dirname(os.path.abspath(__file__))
VIVADO_BAT = r"D:\Vivado\Vivado\2023.2\bin\vivado.bat"
TCL_SCRIPT = os.path.join(WORKING_DIR, "hw_test_control.tcl")
RESULTS_PLOT = os.path.join(WORKING_DIR, "live_sine_wave_plot.png")

def run_infinite_hil_stream():
    print("=========================================================")
    print("[*] 1kHz SAR ADC 가상 정현파 실시간 스트리밍 시스템")
    print("[*] 수집을 종료하고 결과 그래프를 보려면 'Ctrl + C'를 누르세요.")
    print("=========================================================")
    
    if not os.path.exists(VIVADO_BAT):
        print(f"[!] 에러: Vivado 경로가 올바르지 않습니다.\n입력된 경로: {VIVADO_BAT}")
        return

    if not os.path.exists(TCL_SCRIPT):
        print(f"[!] 에러: 매핑할 TCL 스크립트 파일이 없습니다.\n확인된 경로: {TCL_SCRIPT}")
        return

    # Vivado 배치 모드 실행 및 양방향 실시간 파이프 통신 설정
    cmd = [VIVADO_BAT, "-mode", "batch", "-source", TCL_SCRIPT]
    process = subprocess.Popen(
        cmd, 
        stdout=subprocess.PIPE, 
        stderr=subprocess.STDOUT, 
        text=True, 
        encoding='cp949', 
        errors='ignore'
    )

    adc_raw_data = []
    print("[*] Vivado Hardware Manager 하드웨어 세션 초기화 중... 잠시만 기다려주세요.")

    try:
        # Vivado 콘솔 출력을 한 줄씩 실시간으로 가로채기
        for line in process.stdout:
            clean_line = line.strip()
            
            # [수정] 최신 Tcl 스크립트의 정상 접속 모니터링 출력 매칭
            if "TCL_STATUS:" in clean_line:
                print(f"\n  [Vivado] {clean_line}")
                continue
            
            # [수정] 최신 Tcl 스크립트가 뱉는 무한 스트리밍 데이터 포맷 파싱
            if "STREAM_DATA:" in clean_line:
                try:
                    # STREAM_DATA: 뒤의 16진수 문자열 추출 (예: STREAM_DATA:a5 -> a5)
                    parts = clean_line.split("STREAM_DATA:")
                    hex_val = parts[1].strip().replace("0x", "")
                    
                    # 16진수를 10진수 정수(0~255)로 변환하여 리스트에 축적
                    dec_val = int(hex_val, 16)
                    adc_raw_data.append(dec_val)
                    
                    # 콘솔창에 데이터가 수집되는 현황을 실시간 리프레시 형태로 표시
                    print(f"\r[수집 중] 샘플 개수: {len(adc_raw_data)}개 | 현재 ADC 변환 출력값: {dec_val} (0x{hex_val.upper()})", end="")
                    
                    # 오래 켜두어도 버퍼 메모리가 과부하되지 않도록 차트 최대 샘플 수 제한
                    if len(adc_raw_data) > 1500:
                        adc_raw_data.pop(0)
                        
                except (ValueError, IndexError):
                    pass
            
            # [수정] 주석으로 처리된 에러 구문을 진짜 에러로 오인하는 버그 수정
            elif "ERROR:" in clean_line and not clean_line.startswith("#"):
                print(f"\n[!] Vivado 하드웨어 통신 에러 발생: {clean_line}")

    except KeyboardInterrupt:
        # 사용자가 Ctrl + C를 누르면 이 블록으로 떨어짐
        print("\n\n[*] 사용자가 종료 신호(Ctrl+C)를 입력했습니다.")
        print("[*] 하드웨어 커넥션을 안전하게 해제하고 데이터 시각화를 시작합니다...")
        
    finally:
        # 백그라운드에서 실행 중인 Vivado 프로세스를 강제 종료하여 JTAG 자원 반환
        process.terminate()
        try:
            process.wait(timeout=2)
        except subprocess.TimeoutExpired:
            process.kill()

    # 수집된 정현파 데이터 시각화 및 이미지 저장
    if adc_raw_data:
        print(f"\n[*] 총 {len(adc_raw_data)}개의 데이터로 복원 그래프 플로팅 중...")
        
        plt.figure(figsize=(12, 6))
        # 연속된 신호선으로 부드럽게 표현 (초록색 선)
        plt.plot(adc_raw_data, 'g-', linewidth=2, label='S/H Digital Twin Input Sine')
        # 각 클럭 단계의 변환 포인트 점으로 표시 (붉은색 점)
        plt.plot(adc_raw_data, 'ro', markersize=2, alpha=0.3, label='ADC Conversion Bits')
        
        plt.title('SAR ADC Real-Time HIL Stream Test (1kHz Clock Synchronized)', fontsize=14)
        plt.xlabel('Time Step (Sample Index)', fontsize=12)
        plt.ylabel('8-Bit ADC Digital Output Code (Decimal)', fontsize=12)
        plt.ylim(-10, 265)
        plt.grid(True, linestyle=':')
        plt.legend(loc='upper right')
        
        # 이미지 파일로 저장 후 창 띄우기
        plt.savefig(RESULTS_PLOT)
        print(f"[✔] 그래프 생성이 완료되었습니다: {RESULTS_PLOT}")
        plt.show()
    else:
        print("\n[!] 수집된 변환 결과 데이터가 없어 그래프를 띄울 수 없습니다.")
        print("[!] 하드웨어 매니저 close 여부와 .ltx 파일 내 VIO 신호 이름을 재확인하세요.")

if __name__ == "__main__":
    run_infinite_hil_stream()