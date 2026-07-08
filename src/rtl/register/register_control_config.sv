module register_control_config (
    input  logic       iCLK,
    input  logic       iRST,
    input  logic       iWR,
    
    input  logic [7:0] iWDATA,
    output logic [7:0] oRDATA,
    
    output logic       VGD_EN,
    output logic       AUTO_CAL_EN,
    output logic       INT_EN,
    output logic [1:0] TRC_SEL,
    output logic       INT_ACK_OUT,
    output logic       SOFT_RESET_OUT
);

    logic [7:0] reg_data;

    assign VGD_EN       = reg_data[0];
    assign AUTO_CAL_EN  = reg_data[1];
    assign INT_EN       = reg_data[2];
    assign TRC_SEL      = reg_data[4:3];
    assign INT_ACK_OUT  = reg_data[5];

    always_ff @(posedge iCLK or negedge iRST) begin
        if (!iRST) begin
            reg_data        <= 8'h07;
            SOFT_RESET_OUT  <= 1'b0;
        end else begin
            SOFT_RESET_OUT  <= 1'b0;

            if (reg_data[5]) reg_data[5] <= 1'b0;

            if (iWR) begin
                reg_data    <= {1'b0, iWDATA[6:0]};
                if (iWDATA[6]) SOFT_RESET_OUT <= 1'b1;
            end

            if (reg_data[6]) reg_data[6] <= 1'b0;

        end
    end

    assign oRDATA       = reg_data;

endmodule
