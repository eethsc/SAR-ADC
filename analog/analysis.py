import numpy as np
from PyLTSpice import RawRead  # PyLTSpice 라이브러리 사용
import matplotlib.pyplot as plt

# 1. 설정 정보
RAW_FILE = r"D:\Project Folders\LTspice_Repos\ADC\full_ADC\ADC.raw"
V_REF = 3.3  # 회로의 B-Source 가중치 합계 기준
BITS = 8

# 2. 데이터 로드
print(f"파일 읽기 중: {RAW_FILE}...")
ltr = RawRead(RAW_FILE)  # LTSpice RAW 파일 로드[cite: 1]

def get_trace_data(name):
    try:
        return ltr.get_trace(name).get_wave(0)
    except:
        print(f"경고: {name} 트레이스를 찾을 수 없습니다.")
        return None

# 데이터 추출
time = ltr.get_trace('time').get_wave(0)
v_clk = get_trace_data('V(N001)')      # Clock
v_comp = get_trace_data('V(N007)')     # Comparator Out
v_st3 = get_trace_data('V(done)')      # ST3 (Conversion Done)
v_st1 = get_trace_data('V(N008)')       # ST1 (Sampling/Reset)
v_hold = get_trace_data('V(N011)') # S/H Output
v_dac = get_trace_data('V(N009)')     # DAC Output

# 3. 비트 판정 분석 로직
clk_digital = (v_clk > 1.65).astype(int)
rising_edges = np.where(np.diff(clk_digital) == 1)[0]
falling_edges = np.where(np.diff(clk_digital) == -1)[0]

# 변환 종료 시점(ST3 하강 엣지) 기준 분석
done_digital = (v_st3 > 1.65).astype(int)
conv_end_indices = np.where(np.diff(done_digital) == -1)[0]

print("\n" + "="*85)
print(f"{'Cycle':<8} | {'Bit':<4} | {'In[V]':<7} | {'DAC[V]':<7} | {'Comp':<5} | {'Decision'}")
print("-" * 85)

# 상위 3개 변환 사이클 상세 분석 출력
for c_idx, end_pt in enumerate(conv_end_indices[:3]):
    # 해당 사이클 내의 클럭 추출 (약 12us 구간)
    start_pt = end_pt - int(12e-6 / (time[1]-time[0]))
    cycle_clks = rising_edges[(rising_edges > start_pt) & (rising_edges <= end_pt)]
    
    if len(cycle_clks) >= 8:
        for i, clk_pt in enumerate(cycle_clks[:8]):
            v_in = v_hold[clk_pt]
            v_d = v_dac[clk_pt]
            comp = "H" if v_comp[clk_pt] > 2.5 else "L"
            print(f"#{c_idx+1:02d}     | B{7-i}  | {v_in:.3f} | {v_d:.3f} | {comp:<5} | {'Keep' if comp=='H' else 'Drop'}")
    print("-" * 85)

# 4. 시각적 디버깅 그래프 (3단 구성)
fig, (ax1, ax2, ax3) = plt.subplots(3, 1, figsize=(12, 10), sharex=True)

# Plot 1: 아날로그 신호 (추종 성능 확인)
ax1.plot(time*1e6, v_hold, 'b', label='Sampled Input (V_in)')
ax1.plot(time*1e6, v_dac, 'r--', alpha=0.8, label='DAC Trace')
ax1.set_ylabel('Analog Voltage [V]')
ax1.set_title('SAR ADC Verification: Analog vs DAC')
ax1.grid(True)
ax1.legend(loc='upper right')

# Plot 2: 비트 결정 논리 (타이밍 확인)
ax2.step(time*1e6, v_comp, 'g', label='Comparator Out')
ax2.step(time*1e6, v_clk, 'k', alpha=0.2, label='System Clock')
ax2.set_ylabel('Logic [V]')
ax2.grid(True)
ax2.legend(loc='upper right')

# Plot 3: FSM 상태 트레이싱 (ST1 & ST3)
ax3.step(time*1e6, v_st1, 'm', label='ST1 (Sampling Phase)')
ax3.step(time*1e6, v_st3, 'orange', linewidth=2, label='ST3 (Done/Valid)')
ax3.set_xlabel('Time [us]')
ax3.set_ylabel('FSM State [V]')
ax3.set_title('FSM State Monitoring (ST1 & ST3)')
ax3.grid(True)
ax3.legend(loc='upper right')

plt.tight_layout()
plt.show()