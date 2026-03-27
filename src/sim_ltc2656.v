//====================================================================================
//                        ------->  Revision History  <------
//====================================================================================
//
//   Date     Who   Ver  Changes
//====================================================================================
// 25-Mar-26  DWW     1  Initial creation
//====================================================================================

/*
    This module simulates an LTC-2656 eight-channel DAC.

    It simulates the entire DAC command set, but does not simulate either the
    LDAC input or the CLR input.

*/


module sim_ltc2656
(
    input clk,
    input resetn,

    input spi_csld,
    input spi_sck,
    input spi_mosi,
    
    output reg internal_vref,

    output[127:0] dac_output
);
genvar i;

// This is the special value for "channel" that means "this command
// applies to all channels"
localparam[3:0] ALL_CHANNELS = 4'b1111;

// This is a "NO OP" command to the DAC
localparam[3:0] NOP = 4'b1111;

//=============================================================================
// Here we clock in bits from "spi_mosi" on every rising edge of "sck"
//
// The 24 bits most recently clocked in are always in "input_word"
//=============================================================================
reg       previous_spi_sck;
reg[23:0] input_word;
//-----------------------------------------------------------------------------
always @(posedge clk) begin
    if (resetn == 0) begin
        input_word       <= {NOP, 20'b0};
        previous_spi_sck <= 0;
    end else begin
        if (previous_spi_sck == 0 && spi_sck == 1) begin
            input_word <= (input_word << 1) | spi_mosi;
        end
        previous_spi_sck <= spi_sck;
    end
end
//=============================================================================

// Carve up the input word into fields
wire[ 3:0] cmd     = input_word[23:20];
wire[ 3:0] channel = input_word[19:16];
wire[15:0] value   = input_word[15:00];


// The voltage being output on the output pin of each channel
reg[15:0] dac_voltage[0:7];

// The DAC value that is buffered for each channel
reg[15:0] dac_buffer[0:7];

// Pack the dac_voltage[] array into the "dac_output" port
for (i=0; i<8; i=i+1) begin
    assign dac_output[i*16 +: 16] = dac_voltage[i];
end


//=============================================================================
// Perform edge detection on spi_csld
//=============================================================================
reg prior_csld;
always @(posedge clk) begin
    if (resetn == 0)
        prior_csld <= 0;
    else
        prior_csld <= spi_csld;
end
wire csld_rising = (prior_csld == 0) & (spi_csld == 1);
//=============================================================================



//=============================================================================
// This state machine carries out a command on the rising edge of spi_csld
//
// The command to be carried out is in the upper 4-bits of the input_word
//=============================================================================
for (i=0; i<8; i=i+1) begin
    always @(posedge clk) begin
        
        if (resetn == 0) begin
            dac_voltage[i] <= 0;
            dac_buffer [i] <= 0;
        end
        
        else if (csld_rising) begin
            case (cmd)

                // Update just the specified channel's buffer
                4'b0000:
                    if (channel == i || channel == ALL_CHANNELS) begin
                        dac_buffer[i] <= value;
                    end

                // Copy the specified channel's buffer to its voltage
                4'b0001:
                    if (channel == i || channel == ALL_CHANNELS) begin
                        dac_voltage[i] <= dac_buffer[i];
                    end

                // Update the specified channel's buffer and copy
                // the buffer to the voltage for every channel
                4'b0010:
                    if (channel == i || channel == ALL_CHANNELS) begin
                        dac_buffer [i] <= value;
                        dac_voltage[i] <= value;
                    end else begin
                        dac_voltage[i] <= dac_buffer[i];
                    end
                
                // Update the buffer and voltage for the specified channel
                4'b0011:
                    if (channel == i || channel == ALL_CHANNELS) begin
                        dac_buffer [i] <= value;
                        dac_voltage[i] <= value;
                    end

                // Set the voltage for this channel to 0
                4'b0100:
                    if (channel == i || channel == ALL_CHANNELS) begin
                        dac_voltage[i] <= 0;
                    end

                // Power down all channels
                4'b0101:
                    begin
                        dac_voltage[i] <= 0;
                    end

            endcase
        end
    end
end
//=============================================================================



//=============================================================================
// This state machine manages the internal voltage reference on rising
// edges of "spi_csld"
//=============================================================================
always @(posedge clk) begin
    if (resetn == 0) begin
        internal_vref <= 1;
    end

    else if (csld_rising) begin
        case (cmd)
            // Power down the entire chip
            4'b0101:    internal_vref <= 0;
            
            // Power up the internal voltage reference
            4'b0110:    internal_vref <= 1;

            // Switch to external voltage reference
            4'b0111:    internal_vref <= 0;
        endcase
    end
end
//=============================================================================


endmodule