-- Synthesizer top-level block
library ieee;
use ieee.std_logic_1164.all;

entity synthesizer is
	generic (
		clk_freq_g 	  : integer := 12288000;
		sample_rate_g : integer := 48000;
		data_width_g  : integer := 16;
		n_keys_g 	  : integer := 4
		);
	port (
		clk 		  : in std_logic;
		rst_n 		  : in std_logic;
		keys_in 	  : in std_logic_vector(n_keys_g-1 downto 0);
		aud_bclk_out  : out std_logic;
		aud_data_out  : out std_logic;
		aud_lrclk_out : out std_logic
	);
end synthesizer;

architecture structural of synthesizer is

	-- Declare components

	component multi_port_adder is
	generic (
		operand_width_g   : integer := 16;
		num_of_operands_g : integer := 4
	);
	port (
		clk   		: in std_logic;
		rst_n 		: in std_logic;
		operands_in : in std_logic_vector(operand_width_g*num_of_operands_g-1 downto 0);
		sum_out 	: out std_logic_vector(operand_width_g-1 downto 0)
	);
	end component;

	component wave_gen is
        generic (
            width_g : integer;
            step_g  : integer := 2
        );
        port (
            clk             : in std_logic;
            rst_n           : in std_logic;
            sync_clear_n_in : in std_logic;
            value_out       : out std_logic_vector(width_g-1 downto 0)
        );
    end component;
	
	component audio_ctrl is
        generic (
            ref_clk_freq_g : integer := 12288000;
            sample_rate_g  : integer := 48000;
            data_width_g   : integer := 16
        );
        port (
            clk           : in std_logic;
            rst_n         : in std_logic;
            left_data_in  : in std_logic_vector(data_width_g-1 downto 0);
            right_data_in : in std_logic_vector(data_width_g-1 downto 0);
            aud_bclk_out  : out std_logic;
            aud_data_out  : out std_logic;
            aud_lrclk_out : out std_logic
        );
    end component;
	
	-- Connection signal from wave_gens to multi_port_adder
	
	signal value_outs_r : std_logic_vector(n_keys_g*data_width_g-1 downto 0);
	
	-- Connection signal from multi_port_adder to audio_ctrl
	
	signal sum_out_r     : std_logic_vector(data_width_g-1 downto 0);
	
begin

	-- Connect the blocks according to the figure
	
	wave_gen_1 : wave_gen
	generic map (
		width_g => data_width_g,
		step_g  => 1
	)
	port map (
		clk 			=> clk,
		rst_n 			=> rst_n,
		sync_clear_n_in => keys_in(0),
		value_out 		=> value_outs_r(data_width_g-1 downto 0)
	);
	
	wave_gen_2 : wave_gen
	generic map (
		width_g => data_width_g,
		step_g 	=> 2
	)
	port map (
		clk 			=> clk,
		rst_n 			=> rst_n,
		sync_clear_n_in => keys_in(1),
		value_out 		=> value_outs_r(2*data_width_g-1 downto data_width_g)
	);
	
	wave_gen_3 : wave_gen
	generic map (
		width_g => data_width_g,
		step_g 	=> 4
	)
	port map (
		clk 			=> clk,
		rst_n 			=> rst_n,
		sync_clear_n_in => keys_in(2),
		value_out 		=> value_outs_r(3*data_width_g-1 downto 2*data_width_g)
	);
	
	wave_gen_4 : wave_gen
	generic map (
		width_g => data_width_g,
		step_g  => 8
	)
	port map (
		clk 			=> clk,
		rst_n 			=> rst_n,
		sync_clear_n_in => keys_in(3),
		value_out 		=> value_outs_r(4*data_width_g-1 downto 3*data_width_g)
	);
	
	multi_port_adder_1 : multi_port_adder
	generic map (
		operand_width_g   => data_width_g,
		num_of_operands_g => n_keys_g
	)
	port map (
		clk 		=> clk,
		rst_n 		=> rst_n,
		operands_in => value_outs_r,
		sum_out 	=> sum_out_r
	);
	
	audio_ctrl_1 : audio_ctrl
	generic map (
		ref_clk_freq_g => clk_freq_g,
		sample_rate_g  => sample_rate_g,
		data_width_g   => data_width_g
	)
	port map (
		clk 		  => clk,
		rst_n 		  => rst_n,
		left_data_in  => sum_out_r,
		right_data_in => sum_out_r,
		aud_bclk_out  => aud_bclk_out,
		aud_data_out  => aud_data_out,
		aud_lrclk_out => aud_lrclk_out
	);

end structural;
