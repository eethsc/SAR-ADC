`timescale 1ns / 1ps

module tb_sar_adc();

    // 1. 신호 정의
    logic clk;
    logic sys_clr_n;
    logic start;
    logic comp_out;
    logic ST1, ST3;
    logic [7:0] dac_bits;

    // 2. DUT 인스턴스화
    SAR_ADC_CORE uut (
        .clk(clk), .sys_clr_n(sys_clr_n), .start(start), .comp_out(comp_out),
        .ST1(ST1), .ST3(ST3),
        .dac0(dac_bits[0]), .dac1(dac_bits[1]), .dac2(dac_bits[2]), .dac3(dac_bits[3]),
        .dac4(dac_bits[4]), .dac5(dac_bits[5]), .dac6(dac_bits[6]), .dac7(dac_bits[7])
    );

    // 3. 아날로그 비교기 모델 (Target = b4)
    logic [7:0] target_val = 8'hB4; 
    assign #1 comp_out = (target_val >= dac_bits) ? 1'b1 : 1'b0;

    always #5 clk = ~clk;

    // 4. SystemVerilog 파일 핸들러 (int 타입 사용)
    int trace_fd;
    int res_fd;

    // 5. 메인 시뮬레이션 제어
    initial begin
        // 파일 생성
        trace_fd = $fopen("sim_trace.csv", "w");
        res_fd   = $fopen("sim_result.txt", "w");

        if (!trace_fd) $display("FATAL ERROR: Could not open trace file.");

        $fdisplay(trace_fd, "Time,CLK,SYS_CLR_N,START,ST0,ST1,ST2,ST3,TC8,SR,OUT_Q,COMP,DAC");
        $fflush(trace_fd); // 헤더 즉시 쓰기

        clk = 0; sys_clr_n = 0; start = 0;
        #20 sys_clr_n = 1;
        #10 start = 1; #10 start = 0;

        // 타임아웃 프로세스 제어 (SystemVerilog)
        fork
            begin
                wait(ST3 == 1'b1);
                #20;
            end
            begin
                #1000;
                $display("ERROR: Simulation Timeout.");
            end
        join_any
        disable fork; // 진행 안 된 프로세스 정리

        // 결과 파일 기록
        $fdisplay(res_fd, "STATUS: %s", (target_val == dac_bits) ? "SUCCESS" : "FAIL");
        $fdisplay(res_fd, "DETAILS: Target %h, Got %h", target_val, dac_bits);
        
        $fflush(res_fd);
        $fclose(res_fd);
        $fclose(trace_fd);
        
        $finish;
    end

    // 6. 실시간 트레이스 로깅
    always @(clk) begin
        if (sys_clr_n && trace_fd) begin
            $fdisplay(trace_fd, "%0d,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%b,%h", 
                      $time, clk, sys_clr_n, start, uut.ST0, uut.ST1, uut.ST2, uut.ST3, 
                      uut.TC8, uut.sr, uut.out_q, comp_out, dac_bits);
            // [핵심] 매 클럭마다 디스크에 강제 저장 (Hang이 걸려도 데이터는 남음)
            $fflush(trace_fd); 
        end
    end

endmodule