file mkdir ./build/synthesis
set Company 		"NSYSU2025HDL"
set Designer 		"Student"

#設定ADFP(16nm)製程路徑
set search_path      "/cad/CBDK/ADFP/Executable_Package/Collaterals/IP/stdcell/N16ADFP_StdCell/CCS/  $search_path"
#設定ADFP(16nm)製程路徑檔，如果有memory compiler的檔案db檔的路徑，記得在這邊設定
set target_library   "N16ADFP_StdCellss0p72vm40c_ccs.db N16ADFP_StdCellff0p88v125c_ccs.db"

set link_library     "* $target_library dw_foundation.sldb"
set symbol_library   "tsmc040.sdb generic.sdb"
set synthetic_library "dw_foundation.sldb"
set hdlin_translate_off_skip_text "TRUE"
set edifout_netlist_only "TRUE"
set verilogout_no_tri true
set hdlin_enable_presto_for_vhdl "TRUE"
set sh_enable_line_editing true
set sh_line_editing_mode emacs
history keep 100
alias h history

#Path_Top:Verilog放置的位置
#Path_Syn:合成後report.txt檔案要放置的根位置，需自行在目錄下創建名為dc_out_file之資料夾
#Dump_file_name:合成後產生檔案之名字
set Path_Top		"./rtl/"
set Path_Syn		"./build/synthesis/"
set Dump_file_name  "vgg16"
#設定Top module 名稱，需跟自行設計之電路的top module name相同
set Top				"vgg16"
#Specify Clock，clock名需和top module中clk port相同
set Clk_pin			"clk"
set Clk_period		"10"

# [ Read Design File ]
#如果設計有parameter設計，read_file指定不能用，需使用analyze + elaborate指令並自行更改路徑
# read_file -format verilog {/home/m103040049/HDL_HW/multiplier.v}
# current_design $Top
analyze -format verilog {
        ./rtl/vgg16.v
    }
elaborate $Top
current_design $Top
#檢查是否讀取成功
link


# [ Setting Clock Constraints, Combinational Circurt USED ]
# set_max_delay $Clk_period  -from [all_inputs] -to [all_outputs]
# create_clock -name $Clk_pin -period $Clk_period

# [ Setting Clock Constraints ]
create_clock -name $Clk_pin -period $Clk_period [get_ports $Clk_pin]
set_fix_hold									[get_clocks $Clk_pin]
set_dont_touch_network						    [get_clocks $Clk_pin]
set_ideal_network								[get_ports $Clk_pin]

#Setting Input / Output Delay
set_input_delay    	0    -clock $Clk_pin [remove_from_collection [all_inputs] [get_ports $Clk_pin]]
set_output_delay   	0    -clock $Clk_pin [all_outputs]

# [ Setting Design Environment ]
set_operating_conditions    -min_library N16ADFP_StdCellff0p88v125c_ccs -min ff0p88v125c \
                            -max_library N16ADFP_StdCellss0p72vm40c_ccs -max ss0p72vm40c



set_wire_load_model -name ZeroWireload -library N16ADFP_StdCellss0p72vm40c_ccs                         
set_wire_load_mode top

# Area Optimization
set_max_area 0

compile

#Change Naming Rule
set bus_inference_style {%s[%d]}
set bus_naming_style {%s[%d]}
set hdlout_internal_busses true
change_names -hierarchy -rule verilog
define_name_rules name_rule -allowed "A-Z a-z 0-9 _" -max_length 255 -type cell
define_name_rules name_rule -allowed "A-Z a-z 0-9 _[]" -max_length 255 -type net
define_name_rules name_rule -map {{"\\*cell\\*""cell"}} 
define_name_rules name_rule -case_insensitive
change_names -hierarchy -rules name_rule
remove_unconnected_ports -blast_buses [get_cells -hierarchical *]

report_timing -significant_digits 6 -sort_by group

#Report
report_timing -path full -delay max -significant_digits 6 -sort_by group > $Path_Syn/1.timing_report_${Dump_file_name}.txt
report_area -hier -nosplit > $Path_Syn/2.area_report_${Dump_file_name}.txt
report_power -analysis_effort low > $Path_Syn/3.power_report_${Dump_file_name}.txt

# #Each Pipeline Delay 
#uplevel #0 { report_timing  -through { step1/* } -path full -delay max -nworst 1 -max_paths 1 -significant_digits 2 -sort_by group } > $Path_Syn/IF.txt
#uplevel #0 { report_timing  -through { step2/* } -path full -delay max -nworst 1 -max_paths 1 -significant_digits 2 -sort_by group } > $Path_Syn/ID.txt
#uplevel #0 { report_timing  -through { step3/* } -path full -delay max -nworst 1 -max_paths 1 -significant_digits 2 -sort_by group } > $Path_Syn/EX.txt
#uplevel #0 { report_timing  -through { stpe4/* } -path full -delay max -nworst 1 -max_paths 1 -significant_digits 2 -sort_by group } > $Path_Syn/WB.txt


#Write out
write -hierarchy -format ddc -output $Path_Syn/${Dump_file_name}.ddc
write -format verilog -hierarchy -output $Path_Syn/${Dump_file_name}.v
write_sdf -version 2.1 -context verilog $Path_Syn/${Dump_file_name}.sdf
write_sdc $Path_Syn/${Dump_file_name}.sdc

# report_clock_gating -gating_elements
exit
