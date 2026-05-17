# =========================================================
# SAR ADC HIL Test Control Script (Final Robust Version)
# =========================================================

open_hw_manager

# 1. 하드웨어 서버 접속
connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target

# 2. 타겟 장치 설정
set device [get_hw_devices xc7z020_1]
current_hw_device $device

# 프로브 파일(.ltx) 로드
set probes_file "D:/Project Folders/LTspice_Repos/ADC/digital/SAR_ADC_Z7/SAR_ADC_Z7.runs/impl_1/sar_adc_top.ltx"

if {[file exists $probes_file]} {
    set_property PROBES.FILE $probes_file $device
    set_property FULL_PROBES.FILE $probes_file $device
    refresh_hw_device $device
    puts "SUCCESS: Debug Probes loaded."
} else {
    puts "ERROR: Probes file not found at $probes_file"
    exit 1
}

# 3. VIO 객체 매핑
set vio_obj [lindex [get_hw_vios -of_objects $device] 0]
if {[llength $vio_obj] == 0} {
    puts "ERROR: VIO core not found."
    exit 1
}
puts "SUCCESS: Found VIO core: $vio_obj"

# [디버그용] 사용 가능한 모든 프로브 이름 출력
puts "--- Available Probes List ---"
foreach p [get_hw_probes -of_objects $vio_obj] {
    puts "  Probe: $p"
}
puts "-----------------------------"

# 4. 신호 매핑 (더 유연한 와일드카드 적용)
# dac_out 대신 dac_vec을 찾도록 수정
set probe_sel   [get_hw_probes *vio_dbg_mode_sel* -of_objects $vio_obj]
set probe_comp  [get_hw_probes *vio_comp_force* -of_objects $vio_obj]
set probe_start [get_hw_probes *vio_start_force* -of_objects $vio_obj]
set probe_dac   [get_hw_probes *dac_vec* -of_objects $vio_obj]

# 매핑 확인
if {[llength $probe_dac] == 0} {
    puts "WARNING: could not find dac_vec probe. trying dac_out..."
    set probe_dac [get_hw_probes *dac_out* -of_objects $vio_obj]
}

# 5. 파일 입출력 준비
set f_in  [open "stimulus.txt" r]
set f_out [open "hw_results.txt" w]
puts $f_out "Input_Comp,Output_DAC"

# 디버그 모드 활성화
set_property OUTPUT_VALUE 1 $probe_sel
commit_hw_vio $probe_sel
after 100

puts "START: Hardware Test Loop..."

# 6. 테스트 루프 실행
while {[gets $f_in line] >= 0} {
    set comp_input [string trim $line]
    if {$comp_input == ""} continue

    # 가상 비교기 값 설정
    set_property OUTPUT_VALUE $comp_input $probe_comp
    commit_hw_vio $probe_comp

    # 가상 Start 펄스 생성 (0 -> 1 -> 0)
    set_property OUTPUT_VALUE 1 $probe_start
    commit_hw_vio $probe_start
    after 20
    set_property OUTPUT_VALUE 0 $probe_start
    commit_hw_vio $probe_start

    # ADC 변환 대기 및 데이터 갱신
    after 200
    refresh_hw_vio $vio_obj
    set dac_hex [get_property INPUT_VALUE $probe_dac]
    
    puts $f_out "$comp_input,$dac_hex"
    puts "Input: $comp_input | Output: $dac_hex"
}

# 7. 마무리
set_property OUTPUT_VALUE 0 $probe_sel
commit_hw_vio $probe_sel

close $f_in
close $f_out
close_hw_manager

puts "FINISH: All tests completed."
exit