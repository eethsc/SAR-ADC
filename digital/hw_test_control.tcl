# hw_test_control.tcl
open_hw_manager

connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target

set device [get_hw_devices xc7z020_1]
current_hw_device $device

# 새로운 랩실 세션 디렉토리 매핑
set probes_file "D:/Sera/Documents/2026-1/electronic circuit lab 1/termp/SAR-ADC/digital/SAR_ADC_Z7/SAR_ADC_Z7.runs/impl_1/sar_adc_top.ltx"

if {[file exists $probes_file]} {
    set_property PROBES.FILE $probes_file $device
    set_property FULL_PROBES.FILE $probes_file $device
    refresh_hw_device $device
    puts "TCL_STATUS: Probes loaded successfully."
} else {
    puts "TCL_STATUS: Target probes file missing."
    exit 1
}

set vio_obj [lindex [get_hw_vios -of_objects $device] 0]
set probe_sel [get_hw_probes *vio_dbg_mode_sel* -of_objects $vio_obj]
set probe_dac [get_hw_probes *dac_vec* -of_objects $vio_obj]

# 가상 정현파 스트리밍 트리거 ON
set_property OUTPUT_VALUE 1 $probe_sel
commit_hw_vio $probe_sel

puts "TCL_STATUS: Hardware streaming loop activated."
flush stdout

# 무한 루프 데이터 로깅 (PC 세션 강제 종료 시까지 지속)
while {1} {
    refresh_hw_vio $vio_obj
    set dac_hex [get_property INPUT_VALUE $probe_dac]
    
    puts "STREAM_DATA:$dac_hex"
    flush stdout
    after 40
}