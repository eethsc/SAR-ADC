# build_sar_adc.tcl
set project_name "SAR_ADC_Z7"
set project_dir "./digital/$project_name"
set part_name "xc7z020clg400-1"

# 1. 기존 프로젝트 정리
if {[file exists $project_dir]} {
    file delete -force $project_dir
}

# 2. 프로젝트 생성 및 소스 추가
create_project $project_name $project_dir -part $part_name -force
add_files -norecurse "digital/sar_adc_top.v"
add_files -fileset constrs_1 -norecurse "digital/zybo_z7.xdc"
update_compile_order -fileset sources_1

# ---------------------------------------------------------
# 3. 디버깅용 IP 생성 (VIO & ILA)
# ---------------------------------------------------------
# VIO 생성
create_ip -name vio -vendor xilinx.com -library ip -version 3.0 -module_name vio_0
set_property -dict [list \
  CONFIG.C_NUM_PROBE_IN {1} \
  CONFIG.C_PROBE_IN0_WIDTH {8} \
  CONFIG.C_NUM_PROBE_OUT {3} \
  CONFIG.C_PROBE_OUT0_WIDTH {1} \
  CONFIG.C_PROBE_OUT1_WIDTH {1} \
  CONFIG.C_PROBE_OUT2_WIDTH {1} \
] [get_ips vio_0]

# ILA 생성 (에러 유발 파라미터 C_ENABLE_VIDEO_DATA 제거)
create_ip -name ila -vendor xilinx.com -library ip -version 6.2 -module_name ila_0
set_property -dict [list \
  CONFIG.C_NUM_OF_PROBES {5} \
  CONFIG.C_PROBE1_WIDTH {8} \
  CONFIG.C_MONITOR_TYPE {Native} \
] [get_ips ila_0]

# IP 출력물 생성 (합성 전 필수 단계)
generate_target all [get_ips]

# ---------------------------------------------------------
# 4. 합성 및 비트스트림 생성
# ---------------------------------------------------------
launch_runs synth_1 -jobs 4
wait_on_run synth_1

if {[get_property PROGRESS [get_runs synth_1]] != "100%"} {
    puts "ERROR: Synthesis failed!"
    exit 1
}

launch_runs impl_1 -to_step write_bitstream -jobs 4
wait_on_run impl_1

if {[get_property PROGRESS [get_runs impl_1]] != "100%"} {
    puts "ERROR: Implementation/Bitstream failed!"
    exit 1
}

# 5. 리포트 추출
open_run impl_1
report_utilization -file "/digital/utilization_report.txt"
report_timing_summary -file "/digital/timing_report.txt"

puts "========================================================="
puts "비트스트림 생성이 완료되었습니다."
puts "========================================================="
exit