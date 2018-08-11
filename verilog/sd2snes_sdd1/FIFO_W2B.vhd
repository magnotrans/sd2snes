----------------------------------------------------------------------------------
-- Company: Traducciones Magno
-- Engineer: Magno
-- 
-- Create Date: 18.03.2018 20:49:09
-- Design Name: 
-- Module Name: FIFO_Input - Behavioral
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

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx leaf cells in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

entity FIFO_W2B is
	Generic( FIFO_DEPTH						: integer := 32;
				PROG_FULL_TH					: integer := 16);
	Port(	clk									: IN 	STD_LOGIC;
   		srst 									: IN 	STD_LOGIC;
   		wr_en									: IN 	STD_LOGIC;
   		din 									: IN 	STD_LOGIC_VECTOR(15 DOWNTO 0);
   		din_strb								: IN	STD_LOGIC_VECTOR(1 downto 0);
    		rd_en									: IN 	STD_LOGIC;
    		valid									: OUT STD_LOGIC;
    		dout									: OUT STD_LOGIC_VECTOR(7 DOWNTO 0);
    		full									: OUT STD_LOGIC;
    		empty									: OUT STD_LOGIC;				
    		prog_full							: OUT STD_LOGIC );
end FIFO_W2B;


architecture Behavioral of FIFO_W2B is

	type FIFO_Array_t							is array(FIFO_DEPTH-1 downto 0) of STD_LOGIC_VECTOR(7 downto 0);
	signal FIFO_Array							: FIFO_Array_t := (others => (others => '0'));
	signal wr_ptr								: integer range 0 to FIFO_DEPTH-1 := 0;
	signal rd_ptr								: integer range 0 to FIFO_DEPTH-1 := 0;
	signal data_cnt							: integer range 0 to FIFO_DEPTH := 0;
	signal valid_i								: STD_LOGIC := '0';
	
begin

	Process( clk )
	Begin
		if rising_edge( clk ) then
			if( srst = '1' ) then
				FIFO_Array						<= (others => (others => '0'));
				wr_ptr							<= 0;
				rd_ptr							<= 0;
				data_cnt							<= 0;
			else
				-- write command
				if( wr_en = '1' ) then
					-- write 2 bytes
					if( din_strb = "11" AND data_cnt < (FIFO_DEPTH-1) ) then
						-- write data to array
						FIFO_Array(wr_ptr)		<= din(7 downto 0);
						FIFO_Array(wr_ptr+1)		<= din(15 downto 8);
						
						-- check write pointer limits
						if( wr_ptr >= (FIFO_DEPTH-2) ) then
							wr_ptr					<= 0;
						else
							wr_ptr					<= wr_ptr + 2;
						end if;
					-- write 1 byte
					elsif( din_strb = "01" AND data_cnt < FIFO_DEPTH ) then
						-- write data to array
						FIFO_Array(wr_ptr)		<= din(7 downto 0);
						
						-- check write pointer limits
						if( wr_ptr >= (FIFO_DEPTH-1) ) then
							wr_ptr					<= 0;
						else
							wr_ptr					<= wr_ptr + 1;
						end if;
					-- write 1 byte
					elsif( din_strb = "10" AND data_cnt < FIFO_DEPTH ) then
						-- write data to array
						FIFO_Array(wr_ptr)		<= din(15 downto 8);
						
						-- check write pointer limits
						if( wr_ptr >= (FIFO_DEPTH-1) ) then
							wr_ptr					<= 0;
						else
							wr_ptr					<= wr_ptr + 1;
						end if;
					end if;
				end if;
	
				-- read command
				if( rd_en = '1' AND valid_i = '1' ) then			
					-- check read pointer limits
					if( rd_ptr = (FIFO_DEPTH-1) ) then
						rd_ptr					<= 0;
					else
						rd_ptr					<= rd_ptr + 1;
					end if;
				end if;
				
				-- occupancy control
				if( wr_en = '1' AND (rd_en = '1' AND valid_i = '1') ) then
					if( din_strb = "11" AND data_cnt < FIFO_DEPTH ) then
						data_cnt					<= data_cnt + 1;
					elsif( din_strb = "00" AND data_cnt > 0 ) then
						data_cnt					<= data_cnt - 1;
					end if;
				elsif( wr_en = '1' AND (rd_en = '0' OR valid_i = '0') ) then
					if( din_strb = "11" AND data_cnt < (FIFO_DEPTH-1) ) then
						data_cnt					<= data_cnt + 2;
					elsif( (din_strb = "01" OR din_strb = "10") AND data_cnt < FIFO_DEPTH ) then
						data_cnt					<= data_cnt + 1;
					end if;
				elsif( wr_en = '0' AND (rd_en = '1' AND valid_i = '1') ) then
					if( data_cnt > 0 ) then
						data_cnt					<= data_cnt - 1;
					end if;
				end if;
			end if;
		end if;
	End Process;
	
	-- first word fall-through
	dout											<= FIFO_Array(rd_ptr);
	valid_i										<= '1' when data_cnt > 0 else '0';
	valid											<= valid_i;
	
	-- flow control signals
	empty											<= '1' when data_cnt = 0 else '0';
	full											<= '1' when data_cnt = FIFO_DEPTH 	OR srst = '1'	else '0';
	prog_full									<= '1' when data_cnt >= PROG_FULL_TH OR srst = '1' 	else '0';
end Behavioral;
