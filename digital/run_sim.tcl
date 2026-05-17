set project_name "SAR_ADC_SIM"
set project_dir "./sim_proj"

if {[file exists $project_dir]} {
    catch {file delete -force $project_dir}
}

create_project $project_name $project_dir -part xc7z020clg400-1 -force
add_files "sar_adc_top.v"
add_files -fileset sim_1 "tb_sar_adc.sv"

set_property top tb_sar_adc [get_filesets sim_1]
update_compile_order -fileset sim_1

if {[catch {launch_simulation} msg]} {
    puts "ERROR: Simulation launch failed: $msg"
    exit 1
}

run 500ns
close_sim
exit