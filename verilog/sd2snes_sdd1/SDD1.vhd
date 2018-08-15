----------------------------------------------------------------------------------
-- Company: Traducciones Magno
-- Engineer: Magno
-- 
-- Create Date: 29.03.2018 19:16:08
-- Design Name: 
-- Module Name: SDD1 - Behavioral
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
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity SDD1 is
	Port(	MCLK 									: in 	STD_LOGIC;
			RESET 								: in 	STD_LOGIC;
			SRAM_CS 								: out STD_LOGIC;
			SRAM_RD 								: out STD_LOGIC;
			SRAM_WR 								: out STD_LOGIC;
			ROM_OE 								: out STD_LOGIC;
			ROM_CS	 							: out STD_LOGIC;
			ROM_ADDR								: out STD_LOGIC_VECTOR(21 downto 0);
			ROM_DATA 							: in 	STD_LOGIC_VECTOR(15 downto 0);
			SNES_ADDR 							: in 	STD_LOGIC_VECTOR(23 downto 0);
			SNES_DATA_IN						: in 	STD_LOGIC_VECTOR(7 downto 0);
			SNES_DATA_OUT						: out STD_LOGIC_VECTOR(7 downto 0);
			SNES_RD								: in 	STD_LOGIC;
			SNES_WR								: in 	STD_LOGIC );
end SDD1;


architecture Behavioral of SDD1 is
	-- number of master clock cycles of ROM time access -> 3 cycles = 129 ns
	--constant ROM_ACCESS_CYCLES					: integer := 3;
	-- number of SD2SNES clock cycles of ROM time access -> 3 cycles = 125 ns
	constant ROM_ACCESS_CYCLES					: integer := 12;

	COMPONENT SDD1_Core is
		Port(	clk 									: in 	STD_LOGIC;
				-- configuration received from DMA
				DMA_Conf_Valid						: in	STD_LOGIC;
				DMA_Transfer_End					: in	STD_LOGIC;
				-- data input from ROM
				ROM_Data_tready 					: out STD_LOGIC;
				ROM_Data_tvalid					: in 	STD_LOGIC;
				ROM_Data_tdata						: in 	STD_LOGIC_VECTOR(15 downto 0);
				ROM_Data_tkeep						: in 	STD_LOGIC_VECTOR(1 downto 0);
				-- data output to DMA
				DMA_Data_tready					: in 	STD_LOGIC;
				DMA_Data_tvalid					: out STD_LOGIC;
				DMA_Data_tdata						: out STD_LOGIC_VECTOR(7 downto 0) );
	END COMPONENT;
	
	type TipoEstado								is(WAIT_START, GET_DMA_CONFIG, START_DECOMPRESSION, WAIT_DMA_TRIGGERED, WAIT_DMA_START_TRANSFER, WAIT_TRANSFER_COMPLETE, END_DECOMPRESSION);
	signal estado									: TipoEstado := WAIT_START;

	signal DMA_Triggered							: STD_LOGIC := '0';
	signal DMA_Channel_Valid					: STD_LOGIC := '0';
	signal DMA_Channel_Select					: integer range 0 to 7 := 0;
	signal DMA_Channel_Select_Mask			: STD_LOGIC_VECTOR(7 downto 0) := X"00";
	signal DMA_Channel_Enable					: STD_LOGIC := '0';
	signal DMA_Channel_Transfer				: STD_LOGIC_VECTOR(3 downto 0) := "0000";
	signal DMA_Target_Register					: STD_LOGIC_VECTOR(19 downto 0) := (others => '0');
	
	type DMA_Src_Addr_t							is array (0 to 7) of STD_LOGIC_VECTOR(23 downto 0);
	type DMA_Size_t								is array (0 to 7) of STD_LOGIC_VECTOR(15 downto 0); 
	signal DMA_Src_Addr							: DMA_Src_Addr_t := (others => (others => '0'));
	signal DMA_Size								: DMA_Size_t := (others => (others => '0'));
	signal Curr_Src_Addr							: STD_LOGIC_VECTOR(23 downto 0) := (others => '0');
	signal Curr_Size								: integer range 0 to 65535 := 0;
	signal ROM_Access_Cnt						: integer range 0 to 15 := 0;
			
	signal Bank_Map_C0							: STD_LOGIC_VECTOR(3 downto 0) := X"0";
	signal Bank_Map_D0							: STD_LOGIC_VECTOR(3 downto 0) := X"1";
	signal Bank_Map_E0							: STD_LOGIC_VECTOR(3 downto 0) := X"2";
	signal Bank_Map_F0							: STD_LOGIC_VECTOR(3 downto 0) := X"3";
	signal ROM_Data_Byte							: STD_LOGIC_VECTOR(7 downto 0) := X"00";
	signal ROM_Data_tready						: STD_LOGIC := '0';
	signal ROM_Data_tvalid						: STD_LOGIC := '0';
	signal ROM_Data_tdata						: STD_LOGIC_VECTOR(15 downto 0) := (others => '0');
	signal ROM_Data_tkeep						: STD_LOGIC_VECTOR(1 downto 0) := (others => '0');
	signal DMA_Data_tready						: STD_LOGIC := '0';
	signal DMA_Data_tvalid						: STD_LOGIC := '0';
	signal DMA_Data_tdata						: STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
	signal DMA_Data_out							: STD_LOGIC_VECTOR(7 downto 0) := (others => '0');
		
	signal FSM_Sniff_DMA_Config				: STD_LOGIC := '0';
	signal FSM_Avoid_Collision					: STD_LOGIC := '0';
	signal FSM_DMA_Transferring				: STD_LOGIC := '0';
	signal FSM_Start_Decompression			: STD_LOGIC := '0';
	signal FSM_End_Decompression				: STD_LOGIC := '0';
	
	signal SNES_RD_Pipe							: STD_LOGIC_VECTOR(1 downto 0) := "11";
	
begin
	-- decode SRAM access [$7X]:[$6000-$7FFF]; be careful with W-RAM $7E and $7F
	Process(SNES_ADDR, SNES_RD, SNES_WR)
	Begin
		if( SNES_RD = '0' OR SNES_WR = '0' ) then
			if( SNES_ADDR(23 downto 19) = B"01110" AND SNES_ADDR(15) = '0' ) then
				SRAM_CS								<= '0';
				SRAM_RD								<= SNES_RD;
				SRAM_WR								<= SNES_WR;
			else
				SRAM_CS								<= '1';
				SRAM_RD								<= '1';
				SRAM_WR								<= '1';
			end if;
		else
			SRAM_CS									<= '1';
			SRAM_RD									<= '1';
			SRAM_WR									<= '1';
		end if;
	End Process;
	
	-- decode ROM access; SNES CPU has priority over decompression core's input FIFO
	Process( SNES_ADDR, SNES_RD, FSM_DMA_Transferring, FSM_Avoid_Collision, Curr_Src_Addr, ROM_Data_tready,
				Bank_Map_C0, Bank_Map_D0, Bank_Map_E0, Bank_Map_F0 )
	Begin
		-- when CPU and SDD1 may collide
		if( FSM_DMA_Transferring = '1' OR (FSM_Avoid_Collision = '1' AND SNES_RD = '1') ) then
			-- check which megabit is mapped onto $C0
			if( Curr_Src_Addr(23 downto 20) = X"C" ) then
				ROM_ADDR								<= Bank_Map_C0(2 downto 0) & Curr_Src_Addr(19 downto 1);
				ROM_CS								<= NOT ROM_Data_tready;
				ROM_OE								<= NOT ROM_Data_tready;
			-- check which megabit is mapped onto $C0
			elsif( Curr_Src_Addr(23 downto 20) = X"D" ) then
				ROM_ADDR								<= Bank_Map_D0(2 downto 0) & Curr_Src_Addr(19 downto 1);
				ROM_CS								<= NOT ROM_Data_tready;
				ROM_OE								<= NOT ROM_Data_tready;			
			-- check which megabit is mapped onto $C0
			elsif( Curr_Src_Addr(23 downto 20) = X"E" ) then
				ROM_ADDR								<= Bank_Map_E0(2 downto 0) & Curr_Src_Addr(19 downto 1);
				ROM_CS								<= NOT ROM_Data_tready;
				ROM_OE								<= NOT ROM_Data_tready;			
			-- check which megabit is mapped onto $C0
			elsif( Curr_Src_Addr(23 downto 20) = X"F" ) then
				ROM_ADDR								<= Bank_Map_F0(2 downto 0) & Curr_Src_Addr(19 downto 1);
				ROM_CS								<= NOT ROM_Data_tready;
				ROM_OE								<= NOT ROM_Data_tready;						
			else
				ROM_ADDR								<= Curr_Src_Addr(22 downto 1);
				ROM_CS								<= '1';
				ROM_OE								<= '1';
			end if;
		elsif( SNES_RD = '0' ) then
			-- check which megabit is mapped onto $C0
			if( SNES_ADDR(23 downto 20) = X"C" ) then
				ROM_ADDR								<= Bank_Map_C0(2 downto 0) & SNES_ADDR(19 downto 1);
				ROM_CS								<= '0';
				ROM_OE								<= '0';
			-- check which megabit is mapped onto $C0
			elsif( SNES_ADDR(23 downto 20) = X"D" ) then
				ROM_ADDR								<= Bank_Map_D0(2 downto 0) & SNES_ADDR(19 downto 1);
				ROM_CS								<= '0';
				ROM_OE								<= '0';			
			-- check which megabit is mapped onto $C0
			elsif( SNES_ADDR(23 downto 20) = X"E" ) then
				ROM_ADDR								<= Bank_Map_E0(2 downto 0) & SNES_ADDR(19 downto 1);
				ROM_CS								<= '0';
				ROM_OE								<= '0';			
			-- check which megabit is mapped onto $C0
			elsif( SNES_ADDR(23 downto 20) = X"F" ) then
				ROM_ADDR								<= Bank_Map_F0(2 downto 0) & SNES_ADDR(19 downto 1);
				ROM_CS								<= '0';
				ROM_OE								<= '0';						
			else
				ROM_ADDR								<= SNES_ADDR(21 downto 0);
				ROM_CS								<= '1';
				ROM_OE								<= '1';
			end if;
		else
			ROM_ADDR									<= SNES_ADDR(21 downto 0);
			ROM_CS									<= '1';
			ROM_OE									<= '1';			
		end if;
	End Process;

	-- decode data bus
	Process(SNES_RD, SNES_ADDR, ROM_DATA)
	Begin
		if( SNES_RD = '0' ) then
			if( SNES_ADDR(0) = '0' ) then
				ROM_Data_Byte						<= ROM_DATA(7 downto 0);
			else
				ROM_Data_Byte						<= ROM_DATA(15 downto 8);
			end if;
		else
			ROM_Data_Byte							<= X"00";
		end if;		
	End Process;
	

	-- S-DD1 register map
	-- 	$4800 = x -> put S-DD1 to sniff configuration for DMA channel x from SNES address bus
	--		$4801 = x -> start decompression from DMA channel x
	--		$4802 = ? -> ???
	-- 	$4803 = ? -> ???
	--		$4804 = x -> maps the x-th megabit in ROM into SNES $C0-$CF 
	--		$4805 = x -> maps the x-th megabit in ROM into SNES $D0-$DF 
	--		$4806 = x -> maps the x-th megabit in ROM into SNES $E0-$EF 
	--		$4807 = x -> maps the x-th megabit in ROM into SNES $F0-$FF
	Process( MCLK )
	Begin
		if rising_edge( MCLK ) then
			if( RESET = '0' ) then
				Bank_Map_C0								<= X"0";
				Bank_Map_D0								<= X"1";
				Bank_Map_E0								<= X"2";
				Bank_Map_F0								<= X"3";
				DMA_Channel_Valid						<= '0';
				DMA_Channel_Select					<= 0;
				DMA_Channel_Select_Mask				<= X"00";
				DMA_Channel_Enable					<= '0';
				DMA_Channel_Transfer					<= "0000";
			else
				-- SNES bank $00
				if( SNES_WR = '0' AND SNES_ADDR(23 downto 4) = X"00480" ) then
					case SNES_ADDR(3 downto 0) is
						-- register $4800
						when X"0" =>
							-- register channel number and mask
							DMA_Channel_Select		<= conv_integer(SNES_DATA_IN(3 downto 0))-1;
							case( SNES_DATA_IN(3 downto 0) ) is
								when X"1" =>
									DMA_Channel_Select_Mask	<= X"01";
								when X"2" =>
									DMA_Channel_Select_Mask	<= X"02";
								when X"3" =>
									DMA_Channel_Select_Mask	<= X"04";
								when X"4" =>
									DMA_Channel_Select_Mask	<= X"08";
								when X"5" =>
									DMA_Channel_Select_Mask	<= X"10";
								when X"6" =>
									DMA_Channel_Select_Mask	<= X"20";
								when X"7" =>
									DMA_Channel_Select_Mask	<= X"40";
								when X"8" =>
									DMA_Channel_Select_Mask	<= X"80";
								when others =>
									DMA_Channel_Select_Mask	<= X"00";
							end case;
							-- if channel is 0, decoding is disabled
							if( SNES_DATA_IN = X"00" ) then	
								DMA_Channel_Valid		<= '0';
							else
								DMA_Channel_Valid		<= '1';
							end if;
							
						-- register $4801
						when X"1" =>
							DMA_Channel_Enable		<= '1';
							DMA_Channel_Transfer		<= SNES_DATA_IN(3 downto 0); 
							
						-- register $4804
						when X"4" =>
							Bank_Map_C0					<= SNES_DATA_IN(3 downto 0); 
													
						-- register $4805
						when X"5" =>
							Bank_Map_D0					<= SNES_DATA_IN(3 downto 0); 

						-- register $4806
						when X"6" =>
							Bank_Map_E0					<= SNES_DATA_IN(3 downto 0); 
													
						-- register $4807
						when X"7" =>
							Bank_Map_F0					<= SNES_DATA_IN(3 downto 0);
							
						when others =>
							DMA_Channel_Valid			<= '0';
							DMA_Channel_Enable		<= '0';
					end case;
				else
					DMA_Channel_Valid					<= '0';
					DMA_Channel_Enable				<= '0';
				end if;
			end if;
		end if;
	End Process;
	
	-- SNES address for DMA register configuration
	DMA_Target_Register								<= X"0043" & conv_std_logic_vector(DMA_Channel_Select, 4);
	
	-- capture DMA configuration from SNES bus
	Process( MCLK )
	Begin
		if rising_edge( MCLK ) then
			if( FSM_Sniff_DMA_Config = '1' AND SNES_WR = '0' ) then
				-- capture source address low byte
				if( SNES_ADDR = DMA_Target_Register & X"2" ) then
					DMA_Src_Addr(DMA_Channel_Select)(7 downto 0)	<= SNES_DATA_IN;
				end if;
				
				if( SNES_ADDR = DMA_Target_Register & X"3" ) then
					DMA_Src_Addr(DMA_Channel_Select)(15 downto 8)<= SNES_DATA_IN;
				end if;
				
				if( SNES_ADDR = DMA_Target_Register & X"4" ) then	
					DMA_Src_Addr(DMA_Channel_Select)(23 downto 16)<= SNES_DATA_IN;
				end if;
				
				if( SNES_ADDR = DMA_Target_Register & X"5" ) then
					DMA_Size(DMA_Channel_Select)(7 downto 0)		<= SNES_DATA_IN;
				end if;
				
				if( SNES_ADDR = DMA_Target_Register & X"6" ) then	
					DMA_Size(DMA_Channel_Select)(15 downto 8)		<= SNES_DATA_IN;
				end if;
				
				if( SNES_ADDR = X"00420B" ) then
					if( (SNES_DATA_IN AND DMA_Channel_Select_Mask) /= X"00" ) then
						DMA_Triggered										<= '1';
					else
						DMA_Triggered										<= '0';
					end if;
				end if;
			else
				DMA_Triggered												<= '0';
			end if;
		end if;
	End Process;
	
	-- FSM for controlling configuration capture, decompression and signalling
	Process( MCLK )
	Begin
		if rising_edge( MCLK ) then
			if( RESET = '0' ) then
				estado									<= WAIT_START;
			else
				case estado is
					-- wait until register $4800 is written
					when WAIT_START =>
						if( DMA_Channel_Valid = '1' ) then
							estado						<= GET_DMA_CONFIG;
						end if;
						
					-- get DMA configuration after writing to $4801
					when GET_DMA_CONFIG =>
						if( DMA_Channel_Enable = '1' ) then
							estado						<= START_DECOMPRESSION;
						end if;
						
					-- update source address and size registers and launch decompression
					when START_DECOMPRESSION =>
						estado							<= WAIT_DMA_TRIGGERED;
						
					-- wait until DMA is triggered writting to $420B; until then, ROM access form SNES 
					-- CPU has priority over decompression core and it is done each rising edge in SNES_RD
					when WAIT_DMA_TRIGGERED =>
						if( DMA_Triggered = '1' ) then
							estado						<= WAIT_DMA_START_TRANSFER;
						end if;
						
					-- wait until DMA starts; we know it starts when source address appears on address bus
					when WAIT_DMA_START_TRANSFER =>
						if( DMA_Src_Addr(DMA_Channel_Select) = SNES_ADDR ) then
							estado						<= WAIT_TRANSFER_COMPLETE;
						end if;
						
					-- wait until all bytes have been transferred
					when WAIT_TRANSFER_COMPLETE =>
						if( Curr_Size = 0 ) then
							estado						<= END_DECOMPRESSION;
						end if;
						
					-- stop decompression
					when END_DECOMPRESSION =>
						estado							<= WAIT_START;
				end case;
			end if;
		end if;
	End Process;
	
	-- get configuration fom SNES data bus
	with estado select
		FSM_Sniff_DMA_Config							<= '1'	when GET_DMA_CONFIG,
																'1'	when START_DECOMPRESSION,
																'1'	when WAIT_DMA_TRIGGERED,
																'0'	when others;
	
	-- waiting for DMA to start
	with estado select
		FSM_Avoid_Collision							<= '1' 	when WAIT_DMA_TRIGGERED,
																'1' 	when WAIT_DMA_START_TRANSFER,
																'0'	when others;
	
	-- signal core to start decompression
	FSM_Start_Decompression							<= '1'	when estado = START_DECOMPRESSION else '0';
	
	-- decompression and DMA transfer in progress
	FSM_DMA_Transferring								<= '1'	when estado = WAIT_TRANSFER_COMPLETE else '0';
	
	-- signal core to stop decompression
	FSM_End_Decompression							<= '1' 	when estado = END_DECOMPRESSION else '0';
	

	-- fetch data from ROM while decompressing
	Process( MCLK )
	Begin
		if rising_edge(MCLK) then	
			-- update source address
			if( FSM_Start_Decompression = '1' ) then
				Curr_Src_Addr							<= DMA_Src_Addr(DMA_Channel_Select);
				ROM_Access_Cnt							<= 0;
			-- after writting to $4801, SNES CPU can fetch new instructions (STA.w $420B and others), so
			-- ROM access must be time multiplexed; when decompressing from S-DD1, ROM is fully time-
			-- allocated to get data (after 3 master cycles)
			elsif( (FSM_DMA_Transferring = '1') OR (FSM_Avoid_Collision = '1' AND SNES_RD = '1') ) then
				if( ROM_Data_tready = '1' ) then
					-- when ROM's access time finish, get data and increment source address
					if( ROM_Access_Cnt = ROM_ACCESS_CYCLES-1 ) then
						ROM_Access_Cnt					<= 0;
						-- if source address is odd, tkeep is "10" to register upper byte and source address
						-- is incremented by 1 to align source address
						if( Curr_Src_Addr(0) = '1' ) then
							Curr_Src_Addr				<= Curr_Src_Addr + 1;
						else
							Curr_Src_Addr				<= Curr_Src_Addr + 2;
						end if;
					else
						ROM_Access_Cnt					<= ROM_Access_Cnt + 1;
					end if;
				else
					ROM_Access_Cnt						<= 0;
				end if;
			else
				ROM_Access_Cnt							<= 0;
			end if;
		end if;	
	End Process;
	
	-- in the third read cycle, data is registered on the FIFO
	ROM_Data_tvalid									<= '1' when (FSM_DMA_Transferring = '1' AND ROM_Access_Cnt = (ROM_ACCESS_CYCLES-1) ) else
																'1' when (FSM_Avoid_Collision = '1' AND SNES_RD = '1' AND ROM_Access_Cnt = (ROM_ACCESS_CYCLES-1) ) else
	 															'0';
	-- if start address is odd, just register upper byte
	ROM_Data_tkeep										<= "10" when Curr_Src_Addr(0) = '1' else "11";
	-- data for decompression is always 16 bits
	ROM_Data_tdata										<= ROM_DATA;
	
	-- decompression core
	SDD1_Descom : SDD1_Core
		Port map(clk 									=> MCLK,
					-- configuration received from DMA
					DMA_Conf_Valid						=> FSM_Start_Decompression,
					DMA_Transfer_End					=> FSM_End_Decompression,
					-- data input from ROM
					ROM_Data_tready 					=> ROM_Data_tready,
					ROM_Data_tvalid					=> ROM_Data_tvalid,
					ROM_Data_tdata						=> ROM_Data_tdata,					
					ROM_Data_tkeep						=> ROM_Data_tkeep,
					-- data output to DMA
					DMA_Data_tready					=> DMA_Data_tready,
					DMA_Data_tvalid					=> DMA_Data_tvalid,
					DMA_Data_tdata						=> DMA_Data_tdata );
		
	-- tri-State Buffer control
	SNES_DATA_OUT										<= DMA_Data_out 	when (FSM_DMA_Transferring = '1') else 
																ROM_Data_Byte	when SNES_RD = '0' else																 
																(others=>'0');
					
	-- send data to SNES while decompressing using DMA
	Process( MCLK )
	Begin
		if rising_edge(MCLK) then
			-- register rising edge in SNES_RD from CPU
			SNES_RD_Pipe								<= SNES_RD_Pipe(0) & SNES_RD;

			-- update transfer size
			if( FSM_Start_Decompression = '1' ) then
				Curr_Size								<= conv_integer(DMA_Size(DMA_Channel_Select));
				DMA_Data_tready						<= '0';
			-- when source address appears on SNES_ADDR bus, data must be read from core's output FIFO
			elsif( FSM_DMA_Transferring = '1' ) then
				if( DMA_Src_Addr(DMA_Channel_Select) = SNES_ADDR ) then
					-- each falling edge in SNES_RD, a data is output from FIFO
					if( DMA_Data_tready = '1' AND DMA_Data_tvalid = '1' ) then
						DMA_Data_tready				<= '0';
					elsif( SNES_RD_Pipe = "10" ) then
						DMA_Data_tready				<= '1';				
					end if;
				end if;
			end if;
			
			-- register decompressed data
			if( DMA_Data_tready = '1' AND DMA_Data_tvalid = '1' ) then
				DMA_Data_out							<= DMA_Data_tdata;
				Curr_Size								<= Curr_Size - 1;
			end if;
		end if;	
	End Process; 
end Behavioral;
