/* 
 * Reference: https://github.com/jbush001/MiteCPU/blob/master/tinyproc.v
 ******************************************** 
 ********* Harvard Architecture CPU *********
 ********************************************
 * 
 Instruction Format:
 * bits: 
 *  11   10    9    8   7   6   5   4   3   2   1
 * [op2  op1  op0] [ O   P   E   R   A   N   D   ]
 * 
 Instruction Set:
 * 000: Add [ acc = acc + memory_op ]
 * 001: Sub [ acc = acc - memory_op ]
 * 110: And [ acc = acc & memory_op ]
 * 010: Load Immediate value [ acc = <val> ]
 * 011: Output accumulator to module's port and Store on RAM as well [ mem[data_addr] = acc AND result = acc ]
 * 100: Conditional Jump [ if acc < 0: ip_next = acc ]
 * 101:	Move memory_op to memory index, which is used to address RAM [ <no operands> ]
 * 111: No Op
 */

/* Definitions and Constants: */
`define PROGRAM_WIDTH 11
`define DATARAM_WIDTH 8
`define RAM_DEPTH 256

`define OPCFIELD 10:8 /* Opcode field */
`define OPEFIELD 7:0 /* Operand field */

/* Typedefs: */
typedef reg[`PROGRAM_WIDTH - 1:0] prog_t;
typedef reg[`DATARAM_WIDTH - 1:0] data_t;

/* Instruction Set: */
typedef enum {
	OP_ADD  /* 000 */ , OP_SUB  /* 001 */, OP_LDI  /* 010 */, OP_ST  /* 011 */, 
	OP_JMP, /* 100 */ OP_INDEX, /* 101 */  OP_AND, /* 110 */ OP_NOOP /* 111 */
} INS_SET;

module core_main (input clk, output reg[`DATARAM_WIDTH - 1:0] result);
	/* Initialize Program Memory using this task: */
	task progmem_initialize; begin
		instr(OP_LDI, 10); /* Load immediate value to acc */
		instr(OP_ST, 0); /* Store that value into data ram[0] and output it into result */
		instr(OP_ADD, 0); /* Add accumulator with ram[0] */
		instr(OP_ADD, 5); /* Add accumulator again with ram[5] */
		instr(OP_ST, 0);
		/* Let's make a jump: */ 
		instr(OP_LDI, 1); /* Load acc = 1 */
		instr(OP_ST, 1); /* Move that into ram[1] */
		instr(OP_LDI, 0); /* Load acc = 0 */
		instr(OP_SUB, 1); /* Subtract acc - ram[1]. Should be -1, thus it'll jumpt on the next instruction: */
		instr(OP_JMP, 'hFE); /* Jump now to address 0xFE */
		
		/* And so on ... */
	end endtask
	
	/* This function fills up the Program Memory one instruction at a time: */
	data_t instr_counter = 0;
	task instr;
		input [2:0] opcode;
		input [7:0] operator;
	begin
		program_mem[instr_counter] = {opcode, operator};
		instr_counter++;
	end
	endtask

/**************************************************/
/*********** START OF CORE DECLARATION ************/
/**************************************************/
	
	/* Program Memory: */
	prog_t program_mem[0:`RAM_DEPTH - 1];
	/* Data Memory: */
	data_t data_mem[0:`RAM_DEPTH - 1];
	
	/* Instruction Pointer: */
	data_t ip = `DATARAM_WIDTH'hFF;
	wire[`DATARAM_WIDTH - 1:0] ip_next = 
		(ir[`OPCFIELD] == OP_JMP && accumulator[7]) ? 
			ir[`OPEFIELD] : /* Jump to <val> if accumulator has a minus sign bit */
			ip + 1; /* IP incremented by 1 */

	/* Registers: */
	prog_t ir = 0; /* Instruction Register */
	data_t accumulator = 0;
	data_t mem_index = 0; /* Memory index, used for addressing RAM */
	data_t memory_op = 0;
	wire[`DATARAM_WIDTH - 1:0] data_addr = ir[`OPEFIELD] + mem_index;
	
	/* Initial process: */
	initial begin
		integer i;
		/* Load up Program memory: */
		progmem_initialize;
		/* Initialize data memory: */
		for(i = 0; i < `RAM_DEPTH - 1; i++) data_mem[i] = 0;
	end
	
	/* For every negative clock edge: */
	always @(negedge clk) begin
		/* Non-blocking sequence: */
		if(ir[`OPCFIELD] == OP_ST) /* If instruction WAS (on posedge) OP_ST, then: */
			data_mem[data_addr] <= accumulator; /* Move accumulator to RAM by using memory_index register */
		else /* Else, for every other instruction, move data from RAM to memory_op: */
			memory_op <= data_mem[data_addr]; /* data_addr should be equal to ir[`OPEFIELD] */
	end
	
	/* For every positive clock edge: */
	always @(posedge clk) begin
		ip <= ip_next; /* Increment instruction pointer */
		ir = program_mem[ip_next]; /* Fetch instruction */
		mem_index <= (ir[`OPCFIELD] == OP_INDEX) ? memory_op : 0;
		
		case(ir[`OPCFIELD]) /* Decode Opcode using last 3 bits */
			OP_ADD: accumulator <= accumulator + memory_op; /* Add */
			OP_SUB: accumulator <= accumulator - memory_op; /* Sub */
			OP_AND: accumulator <= accumulator & memory_op; /* And */
			OP_LDI: accumulator <= ir[`OPEFIELD]; /* Load immediate */
			OP_ST: if(ir[`OPEFIELD] == 0) result <= accumulator; /* Output accumulator out of the module's port */
		endcase
	end
	
/**************************************************/
/*********** END OF CORE DECLARATION **************/
/**************************************************/
endmodule

 /* (1 ns reference, 1 ps precision): */
`timescale 1ns / 1ps

module core_main_tb;
	reg clk = 0;
	wire[7:0] result;
	
	core_main core(clk, result);
	
	initial begin
		$dumpfile("core_main.vcd");
		$dumpvars(0, core_main_tb);
		$display("CPU Running!");
		repeat(300) #0.001 clk = ~clk;
		$display("Finished! (ret: %02x)", result);
	end
endmodule