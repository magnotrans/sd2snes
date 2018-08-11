----------------------------------------------------------------------------------
-- Company: Traducciones Magno
-- Engineer: Magno
-- 
-- Create Date: 18.03.2018 18:59:09
-- Design Name: 
-- Module Name: Input_Manager - Behavioral
-- Project Name: 
-- Target Devices: 
-- Tool Versions: 
-- Description: 
-- 
-- Dependencies: 
-- 
-- Revision:
-- Revision 0.01 - File Created
-- Additional Comments:
-- 
----------------------------------------------------------------------------------


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;
use IEEE.STD_LOGIC_ARITH.ALL;
use IEEE.STD_LOGIC_UNSIGNED.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity Input_Manager is
	Port(	clk 									: in 	STD_LOGIC;
			-- control data
			DMA_Conf_Valid						: in	STD_LOGIC;
			DMA_In_Progress					: in	STD_LOGIC;
			Header_Valid						: out	STD_LOGIC;
			Header_BPP							: out	STD_LOGIC_VECTOR(1 downto 0);
			Header_Context						: out	STD_LOGIC_VECTOR(1 downto 0);
    		-- data input from ROM
			ROM_Data_tready 					: out STD_LOGIC;
			ROM_Data_tvalid					: in 	STD_LOGIC;
			ROM_Data_tdata						: in 	STD_LOGIC_VECTOR(15 downto 0);
			ROM_Data_tkeep						: in 	STD_LOGIC_VECTOR(1 downto 0);
			-- Golomb decoded value
			Decoded_Bit_tready				: in 	STD_LOGIC;
			Decoded_Bit_tuser					: in 	STD_LOGIC_VECTOR(2 downto 0);
			Decoded_Bit_tvalid				: out STD_LOGIC;
			Decoded_Bit_tdata					: out STD_LOGIC;
			Decoded_Bit_tlast					: out STD_LOGIC);
end Input_Manager;


architecture Behavioral of Input_Manager is
	
	COMPONENT FIFO_W2B
		GENERIC( FIFO_DEPTH					: integer;
					PROG_FULL_TH				: integer);
		PORT(	clk								: IN 	STD_LOGIC;
    			srst 								: IN 	STD_LOGIC;
    			wr_en								: IN 	STD_LOGIC;
    			din 								: IN 	STD_LOGIC_VECTOR(15 DOWNTO 0);
    			din_strb							: IN	STD_LOGIC_VECTOR(1 downto 0);
    			rd_en								: IN 	STD_LOGIC;
    			valid								: OUT STD_LOGIC;
    			dout								: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    			full								: OUT STD_LOGIC;
    			empty								: OUT STD_LOGIC;				
    			prog_full						: OUT STD_LOGIC );
	END COMPONENT;
	
	COMPONENT Serializer
		Port(	clk									: IN 	STD_LOGIC;
				Rst									: IN	STD_LOGIC;
				FIFO_tready							: OUT	STD_LOGIC;
	   		FIFO_tvalid							: IN 	STD_LOGIC;
	   		FIFO_tdata							: IN 	STD_LOGIC_VECTOR(7 DOWNTO 0);
	    		Shift									: IN 	STD_LOGIC;
	    		Shift_cnt							: IN	STD_LOGIC_VECTOR(2 downto 0);
	    		Serial_tvalid						: OUT	STD_LOGIC;
	    		Serial_tdata						: OUT STD_LOGIC_VECTOR(7 downto 0) );
	END COMPONENT;
	 
	COMPONENT Golomb_N_Decoder
		Generic( N									: integer);
		Port(	clk									: IN 	STD_LOGIC;
				rst									: IN	STD_LOGIC;
	   		din_tready							: OUT	STD_LOGIC;
	   		din_tdata							: IN 	STD_LOGIC_VECTOR(N DOWNTO 0);
	   		din_tuser							: OUT	STD_LOGIC_VECTOR(2 downto 0);
	    		dout_tready							: IN 	STD_LOGIC;
	    		dout_tdata							: OUT STD_LOGIC;
	    		dout_tlast							: OUT STD_LOGIC);
	END COMPONENT;
	
	COMPONENT Golomb_0_Decoder
		Port(	clk									: IN 	STD_LOGIC;
				rst									: IN	STD_LOGIC;
	   		din_tready							: OUT	STD_LOGIC;
	   		din_tdata							: IN 	STD_LOGIC_VECTOR(0 DOWNTO 0);
	   		din_tuser							: OUT	STD_LOGIC_VECTOR(2 downto 0);
	    		dout_tready							: IN 	STD_LOGIC;
	    		dout_tdata							: OUT STD_LOGIC;
	    		dout_tlast							: OUT STD_LOGIC);
	END COMPONENT;

	type TipoEstado							is( WAIT_START, FILL_SERIALIZER, GET_HEADER, INIT_GOLOMB, WAIT_END);
	signal estado								: TipoEstado := WAIT_START;
	
	signal Decoded_Bit_tlast_i				: STD_LOGIC := '0';
	signal Decoded_Bit_tdata_i				: STD_LOGIC := '0';
	signal Decoded_Bit_tuser_i				: STD_LOGIC_VECTOR(2 downto 0) := "000";

	signal FIFO_wr								: STD_LOGIC := '0';
	signal FIFO_rd								: STD_LOGIC := '0';
	signal FIFO_Full							: STD_LOGIC := '1';
	signal FIFO_valid							: STD_LOGIC := '0';
	signal FIFO_Data							: STD_LOGIC_VECTOR(7 downto 0) := (others => '0');

	signal Bit_Shift_Rdy						: STD_LOGIC := '0';
	signal Bit_Shift_Cnt						: STD_LOGIC_VECTOR(2 downto 0) := "000";
	signal Bit_Serializer_tvalid			: STD_LOGIC := '0';
	signal Bit_Serializer_tdata			: STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
	
	signal Gx_Run_End							: STD_LOGIC := '0';
	signal G0_Run_End							: STD_LOGIC := '0';
	signal G1_Run_End							: STD_LOGIC := '0';
	signal G2_Run_End							: STD_LOGIC := '0';
	signal G3_Run_End							: STD_LOGIC := '0';
	signal G4_Run_End							: STD_LOGIC := '0';
	signal G5_Run_End							: STD_LOGIC := '0';
	signal G6_Run_End							: STD_LOGIC := '0';
	signal G7_Run_End							: STD_LOGIC := '0';
	signal G0_din								: STD_LOGIC_VECTOR(0 downto 0) := (others => '0');
	signal G1_din								: STD_LOGIC_VECTOR(1 downto 0) := (others => '0');
	signal G2_din								: STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
	signal G3_din								: STD_LOGIC_VECTOR(3 downto 0) := (others => '0');
	signal G4_din								: STD_LOGIC_VECTOR(4 downto 0) := (others => '0');
	signal G5_din								: STD_LOGIC_VECTOR(5 downto 0) := (others => '0');
	signal G6_din								: STD_LOGIC_VECTOR(6 downto 0) := (others => '0');
	signal G7_din								: STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
	signal G0_shift							: STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
	signal G1_shift							: STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
	signal G2_shift							: STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
	signal G3_shift							: STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
	signal G4_shift							: STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
	signal G5_shift							: STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
	signal G6_shift							: STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
	signal G7_shift							: STD_LOGIC_VECTOR(2 downto 0) := (others => '0');
	signal Decoded_G0_tready				: STD_LOGIC := '0';
	signal Decoded_G0_tdata					: STD_LOGIC := '0';
	signal Decoded_G0_tlast					: STD_LOGIC := '0';
	signal Decoded_G1_tready				: STD_LOGIC := '0';
	signal Decoded_G1_tdata					: STD_LOGIC := '0';
	signal Decoded_G1_tlast					: STD_LOGIC := '0';
	signal Decoded_G2_tready				: STD_LOGIC := '0';
	signal Decoded_G2_tdata					: STD_LOGIC := '0';
	signal Decoded_G2_tlast					: STD_LOGIC := '0';
	signal Decoded_G3_tready				: STD_LOGIC := '0';
	signal Decoded_G3_tdata					: STD_LOGIC := '0';
	signal Decoded_G3_tlast					: STD_LOGIC := '0';
	signal Decoded_G4_tready				: STD_LOGIC := '0';
	signal Decoded_G4_tdata					: STD_LOGIC := '0';
	signal Decoded_G4_tlast					: STD_LOGIC := '0';
	signal Decoded_G5_tready				: STD_LOGIC := '0';
	signal Decoded_G5_tdata					: STD_LOGIC := '0';
	signal Decoded_G5_tlast					: STD_LOGIC := '0';
	signal Decoded_G6_tready				: STD_LOGIC := '0';
	signal Decoded_G6_tdata					: STD_LOGIC := '0';
	signal Decoded_G6_tlast					: STD_LOGIC := '0';
	signal Decoded_G7_tready				: STD_LOGIC := '0';
	signal Decoded_G7_tdata					: STD_LOGIC := '0';
	signal Decoded_G7_tlast					: STD_LOGIC := '0';
		
	signal FSM_Reset_FIFO					: STD_LOGIC := '1';
	signal FSM_Get_Header					: STD_LOGIC := '0';
	signal FSM_Load_Golomb					: STD_LOGIC := '0';

begin  
	-- module output tready
	ROM_Data_tready									<= NOT FIFO_Full;
	
	-- FIFO for input words from ROM, that converts to byte data; FIFO is kept mid-full with 4 words
	-- (64 bits); worst IO rate case is 8 output bits * 8 bits per G7 code = 64 bits = 8 byte
	FIFO_wr												<= ROM_Data_tvalid AND NOT FIFO_Full;
	Input_Data : FIFO_W2B
		--Generic map(32, 16)
		Generic map(10, 8)
		Port map(clk									=> clk,
    				srst 									=> FSM_Reset_FIFO,
    				wr_en									=> FIFO_wr,
	    			din 									=> ROM_Data_tdata,
	    			din_strb								=> ROM_Data_tkeep,
	    			rd_en									=> FIFO_rd,
	    			valid									=> FIFO_valid,
	    			dout									=> FIFO_Data,
	    			prog_full							=> FIFO_Full );

   -- convert input bytes to bitstream
	Bitstream : Serializer
   	Port map(clk									=> clk,
   				Rst									=> FSM_Reset_FIFO,
   				FIFO_tready							=> FIFO_rd,
   	   		FIFO_tvalid							=> FIFO_valid,
   	   		FIFO_tdata							=> FIFO_Data,
   	    		Shift									=> Bit_Shift_Rdy,
   	    		Shift_cnt							=> Bit_Shift_Cnt,
   	    		Serial_tvalid						=> Bit_Serializer_tvalid,
   	    		Serial_tdata						=> Bit_Serializer_tdata );

	-- process to register header configuration for decompression; one-cycle strobe signals
	-- data is valid and decompression may start
	Process( clk )
	Begin
		if rising_edge( clk ) then
			if( FSM_Get_Header = '1' ) then
				Header_Valid							<= '1';
				Header_BPP								<= Bit_Serializer_tdata(0) & Bit_Serializer_tdata(1);
				Header_Context							<= Bit_Serializer_tdata(2) & Bit_Serializer_tdata(3);
			else
				Header_Valid							<= '0';
			end if;
		end if;
	End Process;
	
  	-- serializer is updated when last bit in the run is out of any Golomb decoder or after reading header
  	Process( FSM_Load_Golomb, G0_Run_End, G1_Run_End, G2_Run_End, G3_Run_End, G4_Run_End, G5_Run_End, G6_Run_End,
  				G7_Run_End, G0_shift, G1_shift, G2_shift, G3_shift, G4_shift, G5_shift, G6_shift, G7_shift )
  	Begin
  		-- when header is already read, shift first 4 bits
  		if( FSM_Load_Golomb = '1' ) then
  			Bit_Shift_Rdy								<= '1';
  			Bit_Shift_Cnt								<= "011";
  		elsif( G0_Run_End = '1' ) then
   	 	Bit_Shift_Rdy								<= '1';
  			Bit_Shift_Cnt								<= G0_shift;
  		elsif( G1_Run_End = '1' ) then
    	 	Bit_Shift_Rdy								<= '1';
  			Bit_Shift_Cnt								<= G1_shift;
  		elsif( G2_Run_End = '1' ) then
     		Bit_Shift_Rdy								<= '1';
  			Bit_Shift_Cnt								<= G2_shift;
  		elsif( G3_Run_End = '1' ) then
     	 	Bit_Shift_Rdy								<= '1';
  			Bit_Shift_Cnt								<= G3_shift;
  		elsif( G4_Run_End = '1' ) then
     	 	Bit_Shift_Rdy								<= '1';
  			Bit_Shift_Cnt								<= G4_shift;
  		elsif( G5_Run_End = '1' ) then
    	 	Bit_Shift_Rdy								<= '1';
  			Bit_Shift_Cnt								<= G5_shift;
  		elsif( G6_Run_End = '1' ) then
    	 	Bit_Shift_Rdy								<= '1';
  			Bit_Shift_Cnt								<= G6_shift;
  		elsif( G7_Run_End = '1' ) then
    	 	Bit_Shift_Rdy								<= '1';
  			Bit_Shift_Cnt								<= G7_shift;
  		else
  		  	Bit_Shift_Rdy								<= '0';
  			Bit_Shift_Cnt								<= "000";
  		end if;
  	End Process;

  	
  	-- select which Golomb decoder to request the bit to
	Process( clk )
	Begin
		if rising_edge( clk ) then
			Decoded_Bit_tvalid						<= Decoded_Bit_tready;
			
			if( Decoded_Bit_tready = '1' ) then
				Decoded_Bit_tuser_i					<= Decoded_Bit_tuser;
				case( Decoded_Bit_tuser ) is
					when "000" =>
						Decoded_G0_tready				<= '1';
						Decoded_G1_tready				<= '0';
						Decoded_G2_tready				<= '0';
						Decoded_G3_tready				<= '0';
						Decoded_G4_tready				<= '0';
						Decoded_G5_tready				<= '0';
						Decoded_G6_tready				<= '0';
						Decoded_G7_tready				<= '0';
	
					when "001" =>
						Decoded_G0_tready				<= '0';
						Decoded_G1_tready				<= '1';
						Decoded_G2_tready				<= '0';
						Decoded_G3_tready				<= '0';
						Decoded_G4_tready				<= '0';
						Decoded_G5_tready				<= '0';
						Decoded_G6_tready				<= '0';
						Decoded_G7_tready				<= '0';					
	
					when "010" =>
						Decoded_G0_tready				<= '0';
						Decoded_G1_tready				<= '0';
						Decoded_G2_tready				<= '1';
						Decoded_G3_tready				<= '0';
						Decoded_G4_tready				<= '0';
						Decoded_G5_tready				<= '0';
						Decoded_G6_tready				<= '0';
						Decoded_G7_tready				<= '0';
						
					when "011" =>
						Decoded_G0_tready				<= '0';
						Decoded_G1_tready				<= '0';
						Decoded_G2_tready				<= '0';
						Decoded_G3_tready				<= '1';
						Decoded_G4_tready				<= '0';
						Decoded_G5_tready				<= '0';
						Decoded_G6_tready				<= '0';
						Decoded_G7_tready				<= '0';
						
					when "100" =>
						Decoded_G0_tready				<= '0';
						Decoded_G1_tready				<= '0';
						Decoded_G2_tready				<= '0';
						Decoded_G3_tready				<= '0';
						Decoded_G4_tready				<= '1';
						Decoded_G5_tready				<= '0';
						Decoded_G6_tready				<= '0';
						Decoded_G7_tready				<= '0';
					
					when "101" =>
						Decoded_G0_tready				<= '0';
						Decoded_G1_tready				<= '0';
						Decoded_G2_tready				<= '0';
						Decoded_G3_tready				<= '0';
						Decoded_G4_tready				<= '0';
						Decoded_G5_tready				<= '1';
						Decoded_G6_tready				<= '0';
						Decoded_G7_tready				<= '0';
						
					when "110" =>
						Decoded_G0_tready				<= '0';
						Decoded_G1_tready				<= '0';
						Decoded_G2_tready				<= '0';
						Decoded_G3_tready				<= '0';
						Decoded_G4_tready				<= '0';
						Decoded_G5_tready				<= '0';
						Decoded_G6_tready				<= '1';
						Decoded_G7_tready				<= '0';
						
					when "111" =>
						Decoded_G0_tready				<= '0';
						Decoded_G1_tready				<= '0';
						Decoded_G2_tready				<= '0';
						Decoded_G3_tready				<= '0';
						Decoded_G4_tready				<= '0';
						Decoded_G5_tready				<= '0';
						Decoded_G6_tready				<= '0';
						Decoded_G7_tready				<= '1';
						
					when others =>
						Decoded_G0_tready				<= '0';
						Decoded_G1_tready				<= '0';
						Decoded_G2_tready				<= '0';
						Decoded_G3_tready				<= '0';
						Decoded_G4_tready				<= '0';
						Decoded_G5_tready				<= '0';
						Decoded_G6_tready				<= '0';
						Decoded_G7_tready				<= '0';
				end case;
			else
				Decoded_G0_tready						<= '0';
				Decoded_G1_tready						<= '0';
				Decoded_G2_tready						<= '0';
				Decoded_G3_tready						<= '0';
				Decoded_G4_tready						<= '0';
				Decoded_G5_tready						<= '0';
				Decoded_G6_tready						<= '0';
				Decoded_G7_tready						<= '0';
			end if;
		end if;
	End Process;
    
   -- data in for feeding Golomb decoders
  	G0_din												<= Bit_Serializer_tdata(0 downto 0);
   G1_din												<= Bit_Serializer_tdata(1 downto 0);
   G2_din												<= Bit_Serializer_tdata(2 downto 0);
   G3_din												<= Bit_Serializer_tdata(3 downto 0);
   G4_din												<= Bit_Serializer_tdata(4 downto 0);
   G5_din												<= Bit_Serializer_tdata(5 downto 0);
   G6_din												<= Bit_Serializer_tdata(6 downto 0);
   G7_din												<= Bit_Serializer_tdata(7 downto 0);
   
   -- Order 0 Golomb decoder
   G0 : Golomb_0_Decoder
   	Port map(clk									=> clk,
	   			rst									=> FSM_Reset_FIFO,
	   	   	din_tready							=> G0_Run_End,
	   	   	din_tdata							=> G0_din,
		  	   	din_tuser							=> G0_shift,
   		    	dout_tready							=> Decoded_G0_tready,
	   	    	dout_tdata							=> Decoded_G0_tdata,
	   	    	dout_tlast							=> Decoded_G0_tlast );
   
	-- Order 1 Golomb decoder
	G1 : Golomb_N_Decoder
		Generic map( 1 )
		Port map(clk									=> clk,
			   	rst									=> FSM_Reset_FIFO,
	     			din_tready							=> G1_Run_End,
	     			din_tdata							=> G1_din,
	     			din_tuser							=> G1_shift,
	     			dout_tready							=> Decoded_G1_tready,
	       		dout_tdata							=> Decoded_G1_tdata,
	       		dout_tlast							=> Decoded_G1_tlast );
 		
   
	-- Order 2 Golomb decoder
	G2 : Golomb_N_Decoder
		Generic map( 2 )
		Port map(clk									=> clk,
					rst									=> FSM_Reset_FIFO,
	       		din_tready							=> G2_Run_End,
	       		din_tdata							=> G2_din,
	       		din_tuser							=> G2_shift,
	       		dout_tready							=> Decoded_G2_tready,
	       		dout_tdata							=> Decoded_G2_tdata,
	       		dout_tlast							=> Decoded_G2_tlast );
	       		 
	-- Order 3 Golomb decoder
	G3 : Golomb_N_Decoder
		Generic map( 3 )
		Port map(clk									=> clk,
					rst									=> FSM_Reset_FIFO,
	     			din_tready							=> G3_Run_End,
	     			din_tdata							=> G3_din,
	     			din_tuser							=> G3_shift,
	     			dout_tready							=> Decoded_G3_tready,
	       		dout_tdata							=> Decoded_G3_tdata,
	       		dout_tlast							=> Decoded_G3_tlast );

   -- Order 4 Golomb decoder
   G4 : Golomb_N_Decoder
   	Generic map( 4 )
   	Port map(clk									=> clk,
   				rst									=> FSM_Reset_FIFO,
      			din_tready							=> G4_Run_End,
      			din_tdata							=> G4_din,
      			din_tuser							=> G4_shift,
       			dout_tready							=> Decoded_G4_tready,
	       		dout_tdata							=> Decoded_G4_tdata,
	       		dout_tlast							=> Decoded_G4_tlast );
    
	-- Order 5 Golomb decoder
	G5 : Golomb_N_Decoder
		Generic map( 5 )
		Port map(clk									=> clk,
					rst									=> FSM_Reset_FIFO,
	     			din_tready							=> G5_Run_End,
	     			din_tdata							=> G5_din,
	     			din_tuser							=> G5_shift,
	     			dout_tready							=> Decoded_G5_tready,
	       		dout_tdata							=> Decoded_G5_tdata,
	       		dout_tlast							=> Decoded_G5_tlast );

   -- Order 6 Golomb decoder
   G6 : Golomb_N_Decoder
   	Generic map( 6 )
   	Port map(clk									=> clk,
   				rst									=> FSM_Reset_FIFO,
      			din_tready							=> G6_Run_End,
      			din_tdata							=> G6_din,
      			din_tuser							=> G6_shift,
       			dout_tready							=> Decoded_G6_tready,
	       		dout_tdata							=> Decoded_G6_tdata,
	       		dout_tlast							=> Decoded_G6_tlast );
    
	-- Order 7 Golomb decoder
	G7 : Golomb_N_Decoder
		Generic map( 7 )
		Port map(clk									=> clk,
	    			rst									=> FSM_Reset_FIFO,
	     			din_tready							=> G7_Run_End,
	     			din_tdata							=> G7_din,
	     			din_tuser							=> G7_shift,
	     			dout_tready							=> Decoded_G7_tready,
	       		dout_tdata							=> Decoded_G7_tdata,
	       		dout_tlast							=> Decoded_G7_tlast );


	-- multiplexor for routing Golomb decoded bit to module's output
	with Decoded_Bit_tuser_i select
		Decoded_Bit_tdata_i							<= Decoded_G7_tdata	when "111",
																Decoded_G6_tdata	when "110",
																Decoded_G5_tdata	when "101",
																Decoded_G4_tdata	when "100",
																Decoded_G3_tdata	when "011",
																Decoded_G2_tdata	when "010",
																Decoded_G1_tdata	when "001",
																Decoded_G0_tdata	when others;

	with Decoded_Bit_tuser_i select
		Decoded_Bit_tlast_i							<= Decoded_G7_tlast	when "111",
																Decoded_G6_tlast	when "110",
																Decoded_G5_tlast	when "101",
																Decoded_G4_tlast	when "100",
																Decoded_G3_tlast	when "011",
																Decoded_G2_tlast	when "010",
																Decoded_G1_tlast	when "001",
																Decoded_G0_tlast	when others;

	Decoded_Bit_tdata									<= Decoded_Bit_tdata_i;
	Decoded_Bit_tlast									<= Decoded_Bit_tlast_i;
	
	-- FSM for controlling input data into the FIFO and serialized data to
	-- Golomb decoders
	Process( clk )
	Begin
		if rising_edge( clk ) then
			case estado is
				-- keep FIFO reset to avoid filling it with unneeded data;
				-- when DMA configuration is valid, go to next step
				when WAIT_START =>
					if( DMA_Conf_Valid = '1' ) then
						estado							<= FILL_SERIALIZER;
					end if;
	
				-- wait for bit serializer to be ready
				when FILL_SERIALIZER =>
					if( Bit_Serializer_tvalid = '1' ) then
						estado							<= GET_HEADER;
					end if;

				-- read header from bitstream
				when GET_HEADER =>
					estado								<= INIT_GOLOMB; 
					
				-- load Golomb decoders and header
				when INIT_GOLOMB =>
					estado								<= WAIT_END;
			
				-- monitor serializer's bit pointer to ask for new data; if DMA transfer
				-- ends, go to reset state
				when WAIT_END =>
					if( DMA_In_Progress = '0' ) then
						estado							<= WAIT_START;
					end if;
			end case;
		end if;	
	end Process;
	
	-- reset FIFO while decompression is stopped
	FSM_Reset_FIFO										<= '1' when estado = WAIT_START			else '0';
	
	-- enable register to capture header data
	FSM_Get_Header										<= '1' when estado = GET_HEADER			else '0';
	
	-- Golomb decoders are loaded with data at initialization
	with estado select
		FSM_Load_Golomb								<= '1'			when INIT_GOLOMB,
																'0'			when others;
	
end Behavioral;
