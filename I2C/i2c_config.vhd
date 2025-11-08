library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- i2c bus master, DA7212 bus slave

entity i2c_config is
	generic (
		ref_clk_freq_g : integer := 50000000; -- clk freq
		i2c_freq_g     : integer := 20000; -- i2c-bus (sclk_out) freq
		n_params_g     : integer := 15; -- number of configuration params
		n_leds_g       : integer := 4 -- number of leds
	);
	port (
		clk 			         : in std_logic;
		rst_n 			     	 : in std_logic;
		sdat_inout 		    	 : inout std_logic; -- other stuff is output to DA7212, ack/nack input to i2c
		sclk_out 		     	 : out std_logic; -- generate here, rising edge used for sampling data and falling edge to send data
		param_status_out 		 : out std_logic_vector(n_leds_g-1 downto 0); -- debug info, have the 15 params been set?
		finished_out 	   	 	 : out std_logic -- i2c has configured everything (15 transmissions) flag
	);
end i2c_config;

architecture rtl of i2c_config is

	-- ROM and other constants
	
	constant byte_c : integer := 8;
	type register_type is record
		address  : std_logic_vector(byte_c-1 downto 0);
		data     : std_logic_vector(byte_c-1 downto 0);
	end record;
	type ROM_type is array (0 to n_params_g-1) of register_type;
	constant ROM_c : ROM_type := (
		0  => ("00011101", "10000000"), -- cif_ctrl
		1  => ("00100111", "00000100"), -- pll_ctrl
		2  => ("00100010", "00001011"), -- sra
		3  => ("00101000", "00000000"), -- dai_clk_mode
		4  => ("00101001", "10000001"), -- dai_ctrl
		5  => ("01101001", "00001000"), -- dac_l_ctrl
		6  => ("01101010", "00000000"), -- dac_r_ctrl
		7  => ("01000111", "11100001"), -- cp_ctrl
		8  => ("01101011", "00001001"), -- hp_l_ctrl
		9  => ("01101100", "00001000"), -- hp_r_ctrl
		10 => ("01001011", "00001000"), -- mixout_l_select
		11 => ("01001100", "00001000"), -- mixout_r_select
		12 => ("01101110", "10001000"), -- mixout_l_ctrl
		13 => ("01101111", "10001000"), -- mixout_r_ctrl
		14 => ("01010001", "11110001")  -- system_modes_output
	);
	
	constant slave_address_c : std_logic_vector(byte_c-1 downto 0) := "00110100"; -- slave address+write bit
	constant sclk_level_c    : integer := ref_clk_freq_g / (2*i2c_freq_g); -- How many reference clock cycles there are on 1 sclk logic level
	
	-- Essentially these constants and signals ensure that state transitions at STOP do not violate the specified timing constraints

	constant ticks_per_us_c     : integer := ref_clk_freq_g / 1000000;
	constant tsu_sto_cycles_c   : integer := 4  * ticks_per_us_c;  
	constant tbuf_cycles_c      : integer := 5  * ticks_per_us_c;
	signal sto_cnt_r  : integer range 0 to tsu_sto_cycles_c := 0;
	signal buf_cnt_r  : integer range 0 to tbuf_cycles_c    := 0;
	signal hold_sto_r : std_logic := '0';  
	signal wait_buf_r : std_logic := '0';

	-- FSM
	
	type states_type is (START, DATA, ACK, STOP);
	signal current_state_r : states_type;
	
	-- Counters
	
	signal sclk_cnt_r       : integer; -- Keep track whether sclk level should be switched (level switch if sclk_cnt_r = sclk_level_c)
	signal register_cnt_r   : integer; -- Keep track which register+data pair is being configured, also used to determine whether configuration is done i.e. 15 transmissions have successfully been done
	signal byte_cnt_r 	    : integer; -- Keep track how many bytes have been sent (3 bytes / transmission)
	signal bit_cnt_r 	    : integer; -- Keep track how many bits have been sent in the DATA state (8 bits / DATA state visit)
	
	-- Data storage signals
	
	signal sclk_r 	         : std_logic; -- Hold sclk current value, forward to sclk_out
	signal sclk_prev_r 	     : std_logic; -- Detect sclk falling and rising edges
	signal sdat_r 	  	     : std_logic; -- Control sdat_inout (i2c_config controls or releases sdat_inout channel) and data that is sent through it with values '0' and 'Z'
	signal status_r 	     : unsigned(n_leds_g-1 downto 0); -- Track configuration phase, forward to param_status_out
	signal shift_r 		     : std_logic_vector(byte_c-1 downto 0); -- Shift register used for 8-bit value transmissions
	signal finished_out_r    : std_logic; -- Hold information whether configuration is done or not, forward to finished_out
	signal sdat_inout_en_r   : std_logic; -- enable for tri-state
	
begin

	with sdat_inout_en_r select
		sdat_inout 		 <= sdat_r when '1', 'Z' when others;

	sclk_out 		 <= sclk_r;
	param_status_out <= std_logic_vector(status_r);
	finished_out 	 <= finished_out_r;
	
	process(clk, rst_n)
		begin

			-- Init state and values

			if(rst_n = '0') then
			
				current_state_r <= START;
				sclk_cnt_r 		  	<= 0;
				register_cnt_r 		<= 0;
				byte_cnt_r 		  	<= 0;
				bit_cnt_r 		 	<= 0;
				sclk_r 			    <= '1';
				sclk_prev_r 	  	<= '1';
				sdat_r 			    <= '0';
				sdat_inout_en_r 	<= '0';
				status_r 		    <= (others => '0');
				shift_r 		    <= (others => '0');
				finished_out_r 		<= '0';
				sto_cnt_r  			<= 0;
				buf_cnt_r  			<= 0;
				hold_sto_r 			<= '0';
				wait_buf_r 			<= '0';
				
			elsif(clk'event and clk = '1') then
				case current_state_r is
				
					when START =>
					
						if (register_cnt_r = n_params_g) then
							finished_out_r <= '1';
							
						else
						
							-- SCL HIGH in init and after STOP condition
							-- SDAT HIGH/Z in init and after STOP condition
							-- START condition is released on sdat falling transition while SCL HIGH
							
							sdat_r <= '0'; 
							sdat_inout_en_r <= '1';
							current_state_r <= DATA;
							shift_r <= slave_address_c; -- load slave address already
							
						end if;
					
					when DATA =>
					
						-- Generate sclk 
					
						if (sclk_cnt_r = sclk_level_c-1) then
						
							sclk_r <= not sclk_r;
							sclk_prev_r <= sclk_r;
							sclk_cnt_r <= 0;
							
						else
						
							sclk_prev_r <= sclk_r;
							sclk_cnt_r <= sclk_cnt_r+1;
							
						end if;
						
						-- Send data on falling SCLK edge so it will be stable on SCLK high
						
						if (sclk_prev_r = '1' and sclk_r = '0') then

							sdat_inout_en_r <= '1';
						
							if (byte_cnt_r = 0) then -- Slave address
							
								if (bit_cnt_r = byte_c) then
								
									-- Sdat released for DA7212 during ACK state
								
									current_state_r <= ACK;
									sdat_inout_en_r <= '0';
									sclk_cnt_r <= 0;
									bit_cnt_r <= 0;
									byte_cnt_r <= byte_cnt_r+1;
									shift_r <= ROM_c(register_cnt_r).address; -- Load register address
									
								else
								
									-- Send data bit by bit MSB first
								
									bit_cnt_r <= bit_cnt_r+1;
									
									if (shift_r(byte_c-1) = '0') then
										sdat_r <= '0';
										sdat_inout_en_r <= '1';
									else
										sdat_inout_en_r <= '0';
									end if;
									
									shift_r <= shift_r(byte_c-2 downto 0) & '0';
									
								end if;
								
							elsif (byte_cnt_r = 1) then -- Register address
							
								if (bit_cnt_r = byte_c) then
								
									current_state_r <= ACK;
									sdat_inout_en_r <= '0';
									sclk_cnt_r <= 0;
									bit_cnt_r <= 0;
									byte_cnt_r <= byte_cnt_r+1;
									shift_r <= ROM_c(register_cnt_r).data; -- Load actual data
									
								else
								
									bit_cnt_r <= bit_cnt_r+1;
									
									if (shift_r(byte_c-1) = '0') then
										sdat_r <= '0';
										sdat_inout_en_r <= '1';
									else
										sdat_inout_en_r <= '0';
									end if;
									
									shift_r <= shift_r(byte_c-2 downto 0) & '0';
									
								end if;
								
							elsif (byte_cnt_r = 2) then -- Actual data
							
								if (bit_cnt_r = byte_c) then
								
									current_state_r <= ACK;
									sdat_inout_en_r <= '0';
									sclk_cnt_r <= 0;
									bit_cnt_r <= 0;
									byte_cnt_r <= byte_cnt_r+1;
									
								else
								
									bit_cnt_r <= bit_cnt_r+1;
									
									if (shift_r(byte_c-1) = '0') then
										sdat_r <= '0';
										sdat_inout_en_r <= '1';
									else
										sdat_inout_en_r <= '0';
									end if;
									
									shift_r <= shift_r(byte_c-2 downto 0) & '0';
									
								end if;
								
							end if;
						end if;
						
					when ACK => 
					
						if (sclk_cnt_r = sclk_level_c-1) then
						
							sclk_r <= not sclk_r;
							sclk_prev_r <= sclk_r;
							sclk_cnt_r <= 0;
							
						else
						
							sclk_prev_r <= sclk_r;
							sclk_cnt_r <= sclk_cnt_r+1;
							
						end if; 
						
						-- SDA LOW = ACK, SDA HIGH = NACK
						-- Receive data on rising SCLK edge so the data is stable
						
						if (sdat_inout = '0' and sclk_prev_r = '0' and sclk_r = '1') then -- ACK
						
							if (byte_cnt_r = 3) then
							
								-- 3 bytes sent and ACK -> Transmission done except STOP condition
							
								current_state_r <= STOP;
								register_cnt_r <= register_cnt_r+1;
								status_r <= status_r+1;
								byte_cnt_r <= 0;
								sclk_cnt_r <= 0;
								
								
							else
							
								current_state_r <= DATA;
								sclk_cnt_r <= 0;
								
								
							end if;
							
						elsif (sdat_inout /= '0' and sclk_prev_r = '0' and sclk_r = '1') then -- NACK
						
							current_state_r <= STOP;
							byte_cnt_r <= 0;
							sclk_cnt_r <= 0;
							
							
						end if;
						
					when STOP =>
						-- SCL generation: toggle normally unless we’re in the bus-free wait
						if wait_buf_r = '0' then
							if (sclk_cnt_r = sclk_level_c-1) then
							sclk_r      <= not sclk_r;
							sclk_prev_r <= sclk_r;
							sclk_cnt_r  <= 0;
							else
							sclk_prev_r <= sclk_r;
							sclk_cnt_r  <= sclk_cnt_r + 1;
							end if;
						else
							-- Hold SCL high during tBUF
							sclk_r      <= '1';
							sclk_prev_r <= '1';
							sclk_cnt_r  <= 0;
						end if;

						-- While SCL is LOW, keep SDA driven LOW
						if sclk_r = '0' then
							sdat_r          <= '0';
							sdat_inout_en_r <= '1';
						end if;

						-- On SCL rising edge, start the tSU:STO hold (keep SDA low for >= 4us)
						if (sclk_prev_r = '0' and sclk_r = '1' and hold_sto_r = '0' and wait_buf_r = '0') then
							hold_sto_r <= '1';
							sto_cnt_r  <= 0;
						end if;

						-- Count the hold time while SCL is HIGH; after it expires, release SDA to create STOP
						if hold_sto_r = '1' then
							if sto_cnt_r = tsu_sto_cycles_c-1 then
							-- Generate STOP: release SDA while SCL is HIGH
							sdat_inout_en_r <= '0';
							hold_sto_r      <= '0';
							-- Start bus-free gap
							wait_buf_r <= '1';
							buf_cnt_r  <= 0;
							else
							sto_cnt_r <= sto_cnt_r + 1;
							end if;
						end if;

						-- Enforce a small bus-free time tBUF before next START
						if wait_buf_r = '1' then
							if buf_cnt_r = tbuf_cycles_c-1 then
							wait_buf_r      <= '0';
							current_state_r <= START;  -- now it’s legal to pull SDA low again for START
							sclk_cnt_r      <= 0;
							else
							buf_cnt_r <= buf_cnt_r + 1;
							end if;
						end if;

				end case;
			end if;
	end process;
end rtl;
