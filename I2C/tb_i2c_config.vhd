library ieee;
use ieee.std_logic_1164.all;

-------------------------------------------------------------------------------
-- Empty entity
-------------------------------------------------------------------------------

entity tb_i2c_config is
end tb_i2c_config;

-------------------------------------------------------------------------------
-- Architecture
-------------------------------------------------------------------------------
architecture testbench of tb_i2c_config is

  -- Number of parameters to expect
  constant n_params_c     : integer := 15;
  constant n_leds_c       : integer := 4;
  constant i2c_freq_c     : integer := 20000;
  constant ref_freq_c     : integer := 50000000;
  constant clock_period_c : time    := 20 ns;

  -- Every transmission consists several bytes and every byte contains given
  -- amount of bits. 
  constant n_bytes_c       : integer := 3;
  constant bit_count_max_c : integer := 8;

  -- Signals fed to the DUV
  signal clk   : std_logic := '0';  -- Remember that default values supported
  signal rst_n : std_logic := '0';  -- only in synthesis

  -- The DUV prototype
  component i2c_config
    generic (
      ref_clk_freq_g : integer;
      i2c_freq_g     : integer;
      n_params_g     : integer;
	  n_leds_g : integer);
    port (
      clk              : in    std_logic;
      rst_n            : in    std_logic;
      sdat_inout       : inout std_logic;
      sclk_out         : out   std_logic;
      param_status_out : out   std_logic_vector(n_leds_g-1 downto 0);
      finished_out     : out   std_logic
      );
  end component;
  
  -- ROM values and slave address need checking
  
  constant byte_c : integer := 8;
	type register_type is record
		address  : std_logic_vector(byte_c-1 downto 0);
		data     : std_logic_vector(byte_c-1 downto 0);
	end record;
	type ROM_type is array (0 to n_params_c-1) of register_type;
	constant reference_ROM_c : ROM_type := (
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
	
  constant reference_slave_address_c : std_logic_vector(byte_c-1 downto 0) := "00110100";

  -- NACK interval
  
  constant nack_interval_c : integer := 19; 
	
  -- Signals to keep track whether correct bytes are transmitted
  signal shift_r            : std_logic_vector(byte_c-1 downto 0);
  signal slave_address_r    : std_logic_vector(byte_c-1 downto 0);
  signal register_address_r : std_logic_vector(byte_c-1 downto 0);
  signal data_r             : std_logic_vector(byte_c-1 downto 0);

  -- Signals coming from the DUV
  signal sdat         : std_logic := 'Z';
  signal sclk         : std_logic;
  signal param_status : std_logic_vector(n_leds_c-1 downto 0);
  signal finished     : std_logic;

  -- To hold the value that will be driven to sdat when sclk is high.
  signal sdat_r : std_logic;

  -- Counters for receiving bits and bytes, also NACK and register counter
  signal bit_counter_r  : integer range 0 to bit_count_max_c-1;
  signal byte_counter_r : integer range 0 to n_bytes_c-1;
  signal nack_counter_r : integer range 0 to nack_interval_c;
  signal register_cnt_r : integer range 0 to n_params_c;

  -- States for the FSM
  type   states is (wait_start, read_byte, send_ack, wait_stop);
  signal curr_state_r : states;

  -- Previous values of the I2C signals for edge detection
  signal sdat_old_r : std_logic;
  signal sclk_old_r : std_logic;
  
begin  -- testbench

  clk   <= not clk after clock_period_c/2;
  rst_n <= '1'     after clock_period_c*4;

  -- Assign sdat_r when sclk is active, otherwise 'Z'.
  -- Note that sdat_r is usually 'Z'
  with sclk select
    sdat <=
    sdat_r when '1',
    'Z'    when others;


  -- Component instantiation
  i2c_config_1 : i2c_config
    generic map (
      ref_clk_freq_g => ref_freq_c,
      i2c_freq_g     => i2c_freq_c,
      n_params_g     => n_params_c,
	  n_leds_g => n_leds_c)
    port map (
      clk              => clk,
      rst_n            => rst_n,
      sdat_inout       => sdat,
      sclk_out         => sclk,
      param_status_out => param_status,
      finished_out     => finished);

  -----------------------------------------------------------------------------
  -- The main process that controls the behavior of the test bench
  fsm_proc : process (clk, rst_n)
  begin  -- process fsm_proc
    if rst_n = '0' then                 -- asynchronous reset (active low)

      curr_state_r <= wait_start;

      sdat_old_r <= '0';
      sclk_old_r <= '0';

      byte_counter_r <= 0;
      bit_counter_r  <= 0;
	    nack_counter_r <= 0;
	    register_cnt_r <= 0;
	  
	    shift_r         	 <= (others => '0'); 
	    slave_address_r    <= (others => '0');
      register_address_r <= (others => '0');
	    data_r 	           <= (others => '0');

      sdat_r <= 'Z';
      
    elsif clk'event and clk = '1' then  -- rising clock edge

      -- The previous values are required for the edge detection
      sclk_old_r <= sclk;
      sdat_old_r <= sdat;

      -- Falling edge detection for acknowledge control
      -- Must be done on the falling edge in order to be stable during
      -- the high period of sclk
      if sclk = '0' and sclk_old_r = '1' then

        -- If we are supposed to send ack
        if curr_state_r = send_ack then
		
          -- Send ack (low = ACK, high = NACK)

          -- NACK interval
        
          if (nack_counter_r = nack_interval_c) then
          
            sdat_r <= 'Z';
            nack_counter_r <= 0;

          else
          
            sdat_r <= '0';
            nack_counter_r <= nack_counter_r+1;
            
          end if;


        else

          -- Otherwise, sdat is in high impedance state.
          sdat_r <= 'Z';
          
        end if;
        
      end if;


      -------------------------------------------------------------------------
      -- FSM
      case curr_state_r is

        -----------------------------------------------------------------------
        -- Wait for the start condition
        when wait_start =>

          -- While clk stays high, the sdat falls
          if sclk = '1' and sclk_old_r = '1' and
            sdat_old_r /= '0' and sdat = '0' then

            curr_state_r <= read_byte;

          end if;

          --------------------------------------------------------------------
          -- Wait for a byte to be read
        when read_byte =>

          -- Detect a rising edge
          if sclk = '1' and sclk_old_r = '0' then

            if bit_counter_r /= bit_count_max_c-1 then 

              -- Normally just receive a bit
              bit_counter_r <= bit_counter_r + 1;

			        if sdat = '0' then
				
				        shift_r<= shift_r(byte_c-2 downto 0) & '0';

			        else

				        shift_r <= shift_r(byte_c-2 downto 0) & '1';

			        end if;

            else

              -- When terminal count is reached, let's send the ack
              curr_state_r  <= send_ack;
              bit_counter_r <= 0;
			  
              -- Save the received 8 bits into corresponding register
              
              if byte_counter_r = 0 then

                if sdat = '0' then
              
                  slave_address_r <= shift_r(byte_c-2 downto 0) & '0';

                else

                  slave_address_r <= shift_r(byte_c-2 downto 0) & '1';

                end if;
              
              elsif byte_counter_r = 1 then

                if sdat = '0' then
              
                  register_address_r <= shift_r(byte_c-2 downto 0) & '0';

                else

                  register_address_r <= shift_r(byte_c-2 downto 0) & '1';

                end if;
              
              elsif byte_counter_r = 2 then

                if sdat = '0' then
              
                  data_r <= shift_r(byte_c-2 downto 0) & '0';

                else

                  data_r <= shift_r(byte_c-2 downto 0) & '1';
              
                end if;
				      end if;   
            end if;  -- Bit counter terminal count 
          end if;  -- sclk rising clock edge

          --------------------------------------------------------------------
          -- Send acknowledge
        when send_ack => 

          -- Detect a rising edge
          if sclk = '1' and sclk_old_r = '0' then
		  
            -- NACK has occurred, proceed accordingly
            
            if sdat_r = 'Z' then
            
              byte_counter_r <= 0;
              curr_state_r <= wait_stop;
                  
            elsif byte_counter_r /= n_bytes_c-1 then

              -- Transmission continues
              byte_counter_r <= byte_counter_r + 1;
              curr_state_r   <= read_byte;
              
              if byte_counter_r = 0 then
              
                -- Slave address and write bit is verified here
              
                assert slave_address_r = reference_slave_address_c report "Slave address and/or write bit not correct" severity error;
                
              elsif byte_counter_r = 1 then
              
                -- Register address is verified here
              
                assert register_address_r = reference_ROM_c(register_cnt_r).address report "Register address not correct" severity error;
                
              end if;
                    
            else

              -- Transmission is about to stop
              byte_counter_r <= 0;
              curr_state_r   <= wait_stop;
              
              -- Byte counter is 2 at this point so register data is verified
              
              assert data_r = reference_ROM_c(register_cnt_r).data report "Register data is not correct" severity error;
              
              -- Increment register counter on ACK
              
              register_cnt_r <= register_cnt_r+1;
                    
            end if;

          end if;

          ---------------------------------------------------------------------
          -- Wait for the stop condition
        when wait_stop =>

          -- Stop condition detection: sdat rises while sclk stays high
          if sclk = '1' and sclk_old_r = '1' and
            sdat_old_r = '0' and sdat /= '0' then

            curr_state_r <= wait_start;
            
          end if;

      end case;

    end if;
  end process fsm_proc;

  -----------------------------------------------------------------------------
  -- Asserts for verification
  -----------------------------------------------------------------------------

  -- SDAT should never contain X:s.
  assert sdat /= 'X' report "Three state bus in state X" severity error;

  -- End of simulation, but not during the reset
  assert finished = '0' or rst_n = '0' report
    "Simulation done" severity failure;
  
end testbench;
