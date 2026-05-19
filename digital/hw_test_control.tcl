# hw_test_control.tcl (1kHz Hardware Synchronized VIO Polling)
open_hw_manager

connect_hw_server -url localhost:3121 -allow_non_jtag
open_hw_target

set device [get_hw_devices xc7z020_1]
current_hw_device $device

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
set probe_st1 [get_hw_probes -filter {NAME =~ *ST1* || NAME =~ *st1*} -of_objects $vio_obj]
set probe_st3 [get_hw_probes -filter {NAME =~ *ST3* || NAME =~ *st3*} -of_objects $vio_obj]

set st1_ready 1
set st3_ready 1
if {$probe_st1 eq ""} { set probe_st1 $probe_dac; set st1_ready 0 }
if {$probe_st3 eq ""} { set probe_st3 $probe_dac; set st3_ready 0 }

# 가상 정현파 스트리밍 트리거 ON
set_property OUTPUT_VALUE 1 $probe_sel
commit_hw_vio $probe_sel

puts "TCL_STATUS: Hardware streaming loop activated."
flush stdout

# 무한 루프 데이터 초고속 스캔
while {1} {
    if {[catch {
        refresh_hw_vio $vio_obj
        set dac_hex [get_property INPUT_VALUE $probe_dac]
        
        set st1_val "0"
        set st3_val "0"
        if {$st1_ready} { set st1_val [get_property INPUT_VALUE $probe_st1] }
        if {$st3_ready} { set st3_val [get_property INPUT_VALUE $probe_st3] }
        
        # 파이썬으로 콤마 패킷 전송
        puts "STREAM_DATA:$dac_hex,$st1_val,$st3_val"
        flush stdout
    } error_msg]} {
        puts "TCL_STATUS: Streaming warning - $error_msg"
    }
    
    # [수정] 1kHz 클럭의 유효 윈도우를 캐치하기 위해 PC측 샘플링 속도를 5ms로 대폭 단축
    after 5
}