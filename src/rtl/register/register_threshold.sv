module register_threshold (
    input  logic       iCLK,
    input  logic       iRST,
    input  logic       iWR,

    input  logic [7:0] iWDATA,
    output logic [7:0] oRDATA,
    
    output logic [3:0] THRES_VAL,
    output logic [3:0] CAL_PERIOD
);

    logic [7:0] reg_data;

    assign THRES_VAL    = reg_data[3:0];
    assign CAL_PERIOD   = reg_data[7:4];

    always_ff @(posedge iCLK or negedge iRST) begin
        if (!iRST)      reg_data <= 8'h70;
        else if (iWR)   reg_data <= iWDATA;
    end

    assign oRDATA       = reg_data;

endmodule
