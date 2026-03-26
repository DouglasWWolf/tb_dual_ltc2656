//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 25-Mar-26  DWW     1  Initial creation
//====================================================================================

/*
    This module drives a pair of LTC-2656 eight-channel DACs.   We assume that
    the two DACs share a common CS/LD input and share a common SCK input.

    The SCK pins of the DACs are clocked at this modules "clk" frequency 
    divided by 4.   Since the maximum SCK frequency of an LTC-2656 is 50 MHz,
    that means that this module must not be clocked faster than 200 MHz.

    The LTC-2656 supports two commands that are of interest to us:
       (1) Set the value of an channel *without* updating the voltage on the pin
       (2) Set the value of a channel and update the voltages on all pins

    Our programming process is:
       (1) Pulse the CS/LD pin high to cause the previous command to execute
       (2) Send the DAC command to utilize the external voltage reference
       (3) Pulse the CS/LD pin high to cause the previous command to execute
       (4) Send the DAC command to update a channel *without* updating the pin voltage
           (execute steps 3 and 4 a total of 7 times, for channels A thru G)
       (5) Send the DAC command to updated channel H and update all pin voltages

    Note that the command sent to the DAC in step (5) won't be executed until
    the next time we start the programming process!

*/


module dual_ltc2656
(
    input   clk,
    input   resetn,

    // When this strobes high, we program the DACs
    input start_stb,
    
    // These are each eight 16-bit DAC values
    input[127:0] dac_values_0,
    input[127:0] dac_values_1,

    output reg io_csld,   // 0 = Chip-select, rising-edge = execute command
    output reg io_sck,    // SPI serial clock
    output reg io_miso0,  // SPI MISO pin for DAC #0
    output reg io_miso1   // SPI MISO pin for DAC #1
);


//=============================================================================
// These represent the 4 signals of our SPI bus.
// We're going to put them through another level of flops to make it easier
// for logic that may be near the center of the FPGA to make it to the IOB
// registers on the pins at the edge of the FPGA
//=============================================================================
reg spi_csld, spi_sck, spi_miso0, spi_miso1;
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0) begin
        io_csld  <= 0;
        io_sck   <= 0;
        io_miso0 <= 0;
        io_miso1 <= 0;
    end

    else begin
        io_csld  <= spi_csld;
        io_sck   <= spi_sck;
        io_miso0 <= spi_miso0;
        io_miso1 <= spi_miso1;
    end
end
//=============================================================================

// These will contain the commands we're going to send to the DACs
wire[23:0] command_list_0[0:8];
wire[23:0] command_list_1[0:8];

//-----------------------------------------------------------------------------
// These specify DAC output channels
//-----------------------------------------------------------------------------
localparam[3:0] DAC_A = 4'd0;
localparam[3:0] DAC_B = 4'd1;
localparam[3:0] DAC_C = 4'd2;
localparam[3:0] DAC_D = 4'd3;
localparam[3:0] DAC_E = 4'd4;
localparam[3:0] DAC_F = 4'd5;
localparam[3:0] DAC_G = 4'd6;
localparam[3:0] DAC_H = 4'd7;
//-----------------------------------------------------------------------------


//-----------------------------------------------------------------------------
// These are 4-bit commands we can send to the DAC
//-----------------------------------------------------------------------------
localparam[3:0]  DAC_SET_WITHOUT_OUTPUT = 4'b0000;
localparam[3:0]  DAC_SET_AND_OUTPUT_ALL = 4'b0010;
localparam[3:0]  DAC_USE_EXTERNAL_REF   = 4'b0111;
//-----------------------------------------------------------------------------


// Commands to send to DAC #0
assign command_list_0[0] = {DAC_USE_EXTERNAL_REF  , 4'b0 , 16'b0};
assign command_list_0[1] = {DAC_SET_WITHOUT_OUTPUT, DAC_A, dac_values_0[0*16 +: 16]};
assign command_list_0[2] = {DAC_SET_WITHOUT_OUTPUT, DAC_B, dac_values_0[1*16 +: 16]};
assign command_list_0[3] = {DAC_SET_WITHOUT_OUTPUT, DAC_C, dac_values_0[2*16 +: 16]};
assign command_list_0[4] = {DAC_SET_WITHOUT_OUTPUT, DAC_D, dac_values_0[3*16 +: 16]};
assign command_list_0[5] = {DAC_SET_WITHOUT_OUTPUT, DAC_E, dac_values_0[4*16 +: 16]};
assign command_list_0[6] = {DAC_SET_WITHOUT_OUTPUT, DAC_F, dac_values_0[5*16 +: 16]};
assign command_list_0[7] = {DAC_SET_WITHOUT_OUTPUT, DAC_G, dac_values_0[6*16 +: 16]};
assign command_list_0[8] = {DAC_SET_AND_OUTPUT_ALL, DAC_H, dac_values_0[7*16 +: 16]};

// Commands to send to DAC #1
assign command_list_1[0] = {DAC_USE_EXTERNAL_REF  , 4'b0 , 16'b0};
assign command_list_1[1] = {DAC_SET_WITHOUT_OUTPUT, DAC_A, dac_values_1[0*16 +: 16]};
assign command_list_1[2] = {DAC_SET_WITHOUT_OUTPUT, DAC_B, dac_values_1[1*16 +: 16]};
assign command_list_1[3] = {DAC_SET_WITHOUT_OUTPUT, DAC_C, dac_values_1[2*16 +: 16]};
assign command_list_1[4] = {DAC_SET_WITHOUT_OUTPUT, DAC_D, dac_values_1[3*16 +: 16]};
assign command_list_1[5] = {DAC_SET_WITHOUT_OUTPUT, DAC_E, dac_values_1[4*16 +: 16]};
assign command_list_1[6] = {DAC_SET_WITHOUT_OUTPUT, DAC_F, dac_values_1[5*16 +: 16]};
assign command_list_1[7] = {DAC_SET_WITHOUT_OUTPUT, DAC_G, dac_values_1[6*16 +: 16]};
assign command_list_1[8] = {DAC_SET_AND_OUTPUT_ALL, DAC_H, dac_values_1[7*16 +: 16]};


//=============================================================================
// This is an ultra-simple bit-banged SPI where every state of the csld, sck,
// and miso pins lasts for two clock cycles.
//
// To use it, load the two 24-bit output values into pending[0] and pending[1]
// then strobe "bitbang_stb" high for a single cycle.   When "bitbang_idle" 
// goes high, the SPI output is complete.
//    
// Note that this code strobes the spi_csld pin high *before* banging out
// the data bits.  This causes the DACs to execute the previously programmed 
// command just before we program the current command.
//=============================================================================
reg[23:0] pending[0:1];
reg       bitbang_stb;
wire      bitbang_idle;
//-----------------------------------------------------------------------------
reg[ 2:0] bbsm_state;
localparam BBSM_IDLE   = 0;
localparam BBSM_STATE1 = 1;
localparam BBSM_LOOP   = 2;
localparam BBSM_STATE3 = 3;
localparam BBSM_STATE4 = 4;
localparam BBSM_STATE5 = 5;
localparam BBSM_FINAL  = 6;

reg[23:0] shifter[0:1];
reg[ 5:0] bit_count;
assign    bitbang_idle = (bitbang_stb == 0 && bbsm_state == BBSM_IDLE);
//-----------------------------------------------------------------------------
always @(posedge clk) begin

    spi_csld <= 0;

    if (resetn == 0) begin
        bbsm_state <= BBSM_IDLE;
        spi_sck    <= 0;
        spi_miso0  <= 0;
        spi_miso1  <= 0;
    end

    else case (bbsm_state)

    // If we're told to start, raise spi_csld to tell the DACs
    // "Execute the most recently received command"
    BBSM_IDLE:
        if (bitbang_stb) begin
            spi_csld   <=1;
            shifter[0] <= pending[0];
            shifter[1] <= pending[1];
            bit_count  <= 0;
            bbsm_state <= BBSM_STATE1;
        end

    // Keep spi_csld high for a 2nd clock cycle
    BBSM_STATE1:
        begin
            spi_csld   <= 1;
            spi_sck    <= 0;
            spi_miso0  <= 0;
            spi_miso1  <= 0;
            bbsm_state <= BBSM_LOOP;
        end

    // Drive the top bit of data to spi_miso while sck is low
    BBSM_LOOP:
        begin
            spi_sck    <= 0;
            spi_miso0  <= shifter[0][23];
            spi_miso1  <= shifter[1][23];
            bbsm_state <= BBSM_STATE3;
        end

    // Keep driving the top bit of data to spi_miso while sck is low
    BBSM_STATE3:
        begin
            spi_sck    <= 0;
            spi_miso0  <= shifter[0][23];
            spi_miso1  <= shifter[1][23];
            bbsm_state <= BBSM_STATE4;
        end

    // Drive the top bit of data to spi_miso while sck is high
    BBSM_STATE4:
        begin
            spi_sck    <= 1;
            spi_miso0  <= shifter[0][23];
            spi_miso1  <= shifter[1][23];
            bit_count  <= bit_count + 1;
            bbsm_state <= BBSM_STATE5;
        end

    // Keep driving the top bit of data to spi_miso while sck is high
    BBSM_STATE5:
        begin
            spi_sck    <= 1;
            spi_miso0  <= shifter[0][23];
            spi_miso1  <= shifter[1][23];

            shifter[0] <= shifter[0] << 1;
            shifter[1] <= shifter[1] << 1;
            if (bit_count == 24)
                bbsm_state <= BBSM_FINAL;
            else 
                bbsm_state <= BBSM_LOOP;
        end

    // Force sck and the miso pins low in preperation for the 
    // next "bitbang_stb" command
    BBSM_FINAL:
        begin
            spi_sck    <= 0;
            spi_miso0  <= 0;
            spi_miso1  <= 0;
            bbsm_state <= BBSM_IDLE;
        end

    endcase

end
//=============================================================================





//=============================================================================
// When "start_stb" strobes high, this state machine sends all 9 commands
// to their respective DACs.
//=============================================================================
reg      fsm_state;
reg[3:0] next_idx;
//-----------------------------------------------------------------------------
always @(posedge clk) begin

    // This strobes high for one clock cycle at a time
    bitbang_stb <= 0;

    if (resetn == 0) begin
        fsm_state <= 0;
    end

    else case(fsm_state)
        0: if (start_stb) begin
                pending[0]  <= command_list_0[0];
                pending[1]  <= command_list_1[0];
                bitbang_stb <= 1;
                next_idx    <= 1;
                fsm_state   <= 1;               
            end

        1:  if (bitbang_idle) begin
                if (next_idx < 9) begin
                    pending[0]  <= command_list_0[next_idx];
                    pending[1]  <= command_list_1[next_idx];
                    bitbang_stb <= 1;
                    next_idx    <= next_idx + 1;
                end

                else fsm_state <= 0;
            end

    endcase

end
//=============================================================================



endmodule