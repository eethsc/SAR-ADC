import subprocess
import os
import sys

VIVADO_BAT = r"D:\Vivado\Vivado\2023.2\bin\vivado.bat"
BUILD_TCL = "digital/build_sar_adc.tcl"
BUILD_LOG = "digital/vivado_build_log.txt"

def cleanup():
    """파일 점유 방지를 위한 프로세스 정리"""
    try:
        subprocess.run(["taskkill", "/F", "/IM", "vivado.exe"], stdout=subprocess.DEVNULL, stderr=subprocess.DEVNULL)
    except: pass

def run_build_and_analyze():
    print(f"[*] 하드웨어 빌드 프로세스 시작...")
    
    if not os.path.exists(VIVADO_BAT):
        print(f"[!] Vivado 실행 경로를 찾을 수 없습니다.")
        return

    cmd = [VIVADO_BAT, "-mode", "batch", "-source", BUILD_TCL]
    
    try:
        # cp949 인코딩으로 실행 (Windows 한글 환경)
        result = subprocess.run(cmd, capture_output=True, text=True, encoding='cp949', errors='ignore')
        
        with open(BUILD_LOG, "w", encoding='utf-8') as f:
            f.write(result.stdout)
            f.write("\n--- STDERR ---\n")
            f.write(result.stderr)

        if result.returncode == 0:
            print("\n[✔] 빌드 성공! 비트스트림 및 IP 생성이 완료되었습니다.")
        else:
            print("\n[✘] 빌드 중 오류 발생. 상세 분석 결과:")
            analyze_log(result.stdout, result.stderr)

    except Exception as e:
        print(f"[!] 실행 오류: {e}")

def analyze_log(stdout, stderr):
    combined = stdout + "\n" + stderr
    print("-" * 60)
    
    # 1. IP 패키징 에러 체크
    if "Ipptcl 7-1594" in combined or "No core is currently loaded" in combined:
        print("▶ 원인: IP 패키징 중 활성화된 코어를 찾지 못했습니다.")
        print("   조치: ipx::package_project 명령어의 -set_current 옵션을 'true'로 수정했습니다.")
    
    # 2. 파일/경로 관련 에러 체크
    elif "지정된 경로를 찾을 수 없습니다" in combined:
        print("▶ 원인: 내부 임시 파일 생성 중 경로 오류가 발생했습니다.")
        print("   조치: 프로젝트 폴더 내 .Xil 폴더를 삭제하고 다시 시도하세요.")
        
    # 3. 일반 에러 출력
    else:
        errors = [line for line in combined.split('\n') if "ERROR:" in line]
        for err in errors:
            print(f"▶ {err}")
            
    print("-" * 60)
    print(f"상세 로그 파일: {BUILD_LOG}")

if __name__ == "__main__":
    cleanup()
    run_build_and_analyze()