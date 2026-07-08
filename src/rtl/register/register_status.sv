module register_status (
    input  logic       iCLK,
    input  logic       iRST,
    output logic [7:0] oRDATA,
    
    input  logic       iSOFT_RST,
    input  logic       iINT_ACK,

    input  logic [1:0] GLITCH_STATUS,
    input  logic [1:0] ACTIVE_TRC,
    input  logic [3:0] FAILURE_EST
);

    logic [7:0] reg_data;

    always_ff @(posedge iCLK or negedge iRST) begin
        if (!iRST || iSOFT_RST) begin
            reg_data        <= 8'h00;
        end else begin
            reg_data[3:2]   <= ACTIVE_TRC;
            reg_data[7:4]   <= FAILURE_EST;

            if (iINT_ACK) begin
                reg_data[1:0] <= 2'b00;
            end else begin
                if (GLITCH_STATUS[0]) reg_data[0] <= 1'b1;   /* undervoltage */
                if (GLITCH_STATUS[1]) reg_data[1] <= 1'b1;   /* overvoltage */
            end
        end
    end

    assign oRDATA = reg_data;

endmodule
