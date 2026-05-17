`timescale 1ns / 1ps

// ========================================================
// [IP Module] 8-Bit SAR ADC Core 
// (MSB-우선 축차 비교 및 로직 최적화 완료)
// ========================================================
module SAR_ADC_CORE (
    input wire clk,
    input wire sys_clr_n,
    input wire start,
    input wire comp_out,
    output wire ST1,
    output wire ST3,
    output wire dac0, dac1, dac2, dac3, dac4, dac5, dac6, dac7
);
    // 상태 머신 레지스터
    reg S1, S0;
    wire NS1, NS0;
    wire ST0, ST2;
    wire ST1_n;

    assign ST0 = ~S1 & ~S0;   // IDLE
    assign ST1 = ~S1 &  S0;   // SAMPLING
    assign ST2 =  S1 & ~S0;   // QUANTIZATION
    assign ST3 =  S1 &  S0;   // RESULT
    assign ST1_n = ~ST1;

    // 8클럭 카운터
    reg [3:0] cnt;
    wire TC8;
    
    always @(posedge clk or negedge sys_clr_n) begin
        if (!sys_clr_n) cnt <= 4'd0;
        else if (!ST2)  cnt <= 4'd0;
        else            cnt <= cnt + 1'b1;
    end
    assign TC8 = (cnt == 4'd7);

    // 다음 상태 결정 로직
    assign NS1 = ST1 | ST2;
    assign NS0 = (ST0 & start) | (ST2 & TC8) | ST3;

    always @(posedge clk or negedge sys_clr_n) begin
        if (!sys_clr_n) begin
            S1 <= 1'b0; S0 <= 1'b0;
        end else begin
            S1 <= NS1; S0 <= NS0;
        end
    end

    // 8비트 시프트 레지스터 (MSB부터 LSB로 진행되도록 수정)
    wire first_inject;
    reg [7:0] sr;
    assign first_inject = ST2 & (cnt == 4'd0); 

    always @(negedge clk or negedge ST1_n) begin
        if (!ST1_n) sr <= 8'b0;
        else        sr <= {first_inject, sr[7:1]}; 
    end

    // SAR 출력 래치
    reg [7:0] out_q;
    integer i;
    always @(posedge clk or negedge ST1_n) begin
        if (!ST1_n) begin
            out_q <= 8'b0;
        end else begin
            for (i = 0; i < 8; i = i + 1) begin
                if (sr[i]) out_q[i] <= comp_out; 
            end
        end
    end

    // DAC 출력 매핑
    wire [7:0] dac_vec = out_q | sr;
    assign {dac7, dac6, dac5, dac4, dac3, dac2, dac1, dac0} = dac_vec;

endmodule


// ========================================================
// [Top Module] Zybo Z7 Board Wrapper 
// (VIO, ILA 하드웨어 디버깅 및 시뮬레이션 호환)
// ========================================================
module sar_adc_top (
    input  wire sysclk,
    input  wire comp_out,
    output wire led_st3,
    output wire pmod_st1,
    output wire pmod_dac0, pmod_dac1, pmod_dac2, pmod_dac3,
    output wire pmod_dac4, pmod_dac5, pmod_dac6, pmod_dac7
);

    // 1. 내부 신호 선언 (합성 에러 해결을 위해 명확히 선언)
    reg [6:0] clk_div = 0;
    reg adc_clk = 0;
    reg internal_clr_n = 0;
    reg internal_start = 0;
    reg [15:0] timer = 0;

    wire actual_comp;
    wire final_start;
    wire [7:0] dac_vec;

    // VIO 제어용 와이어
    wire vio_dbg_mode_sel;
    wire vio_comp_force;
    wire vio_start_force;

    // 2. 클럭 분주 (125MHz -> 약 1MHz)
    always @(posedge sysclk) begin
        if (clk_div == 7'd62) begin
            clk_div <= 0;
            adc_clk <= ~adc_clk;
        end else begin
            clk_div <= clk_div + 1;
        end
    end

    // 3. 제어 신호 생성
    always @(posedge adc_clk) begin
        timer <= timer + 1;
        if (timer > 16'd10) internal_clr_n <= 1'b1;
        else internal_clr_n <= 1'b0;

        // 주기적인 start 신호 펄스
        if (timer[5:0] == 6'd63) internal_start <= 1'b1;
        else internal_start <= 1'b0;
    end

    // 4. MUX: 실제 핀 입력 vs VIO 가상 입력 선택
    assign actual_comp = vio_dbg_mode_sel ? vio_comp_force  : comp_out;
    assign final_start = vio_dbg_mode_sel ? vio_start_force : internal_start;

    // 5. SAR ADC CORE 인스턴스화
    SAR_ADC_CORE adc_inst (
        .clk(adc_clk),
        .sys_clr_n(internal_clr_n),
        .start(final_start),
        .comp_out(actual_comp),
        .ST1(pmod_st1),
        .ST3(led_st3),
        .dac0(pmod_dac0), .dac1(pmod_dac1), .dac2(pmod_dac2), .dac3(pmod_dac3),
        .dac4(pmod_dac4), .dac5(pmod_dac5), .dac6(pmod_dac6), .dac7(pmod_dac7)
    );

    // ILA 및 VIO 모니터링을 위한 통합 벡터화
    assign dac_vec = {pmod_dac7, pmod_dac6, pmod_dac5, pmod_dac4, pmod_dac3, pmod_dac2, pmod_dac1, pmod_dac0};

    // ---------------------------------------------------------
    // 6. [조건부 컴파일] 디버깅 IP (VIO & ILA) 
    // 시뮬레이션 환경에서는 이 블록이 무시되어 에러를 방지합니다.
    // ---------------------------------------------------------
    `ifndef SIMULATION
        vio_0 u_vio (
          .clk(sysclk),
          .probe_in0(dac_vec),             // 모니터링: 현재 DAC 값
          .probe_out0(vio_dbg_mode_sel),   // 제어: 디버그 모드 ON/OFF
          .probe_out1(vio_comp_force),     // 제어: 가상 비교기 값 (0 or 1)
          .probe_out2(vio_start_force)     // 제어: 가상 변환 시작 트리거
        );

        ila_0 u_ila (
          .clk(adc_clk),
          .probe0(actual_comp),            // 파형 확인: 최종 입력된 비교기 신호
          .probe1(dac_vec),                // 파형 확인: 8-bit DAC 진행 과정
          .probe2(pmod_st1),               // 파형 확인: ST1(Sampling) 상태
          .probe3(led_st3),                // 파형 확인: ST3(Result) 상태
          .probe4(final_start)             // 파형 확인: 변환 시작 트리거
        );
    `else
        // 시뮬레이션 시에는 VIO 신호를 0으로 고정하여 내부 로직에 간섭하지 않음
        assign vio_dbg_mode_sel = 1'b0;
        assign vio_comp_force   = 1'b0;
        assign vio_start_force  = 1'b0;
    `endif

endmodule