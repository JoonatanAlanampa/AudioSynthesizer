library ieee;
use ieee.std_logic_1164.all;

entity audio_codec_model is
    generic (
        data_width_g : integer := 16
    );
    port (
        rst_n           : in std_logic;
        aud_data_in     : in std_logic;
        aud_bclk_in     : in std_logic;
        aud_lrclk_in    : in std_logic;
        value_left_out  : out std_logic_vector(data_width_g-1 downto 0);
        value_right_out : out std_logic_vector(data_width_g-1 downto 0)
    );
end audio_codec_model;

architecture rtl of audio_codec_model is

    type states_type is (wait_for_input, read_left, read_right);
    signal current_state_r : states_type;
    signal left_result_r   : std_logic_vector(data_width_g-1 downto 0);
    signal right_result_r  : std_logic_vector(data_width_g-1 downto 0);
    signal shift_r         : std_logic_vector(data_width_g-1 downto 0);
    signal bit_cnt_r       : integer range 0 to data_width_g-1;
    signal lrclk_prev_r    : std_logic;


begin

    value_left_out  <= left_result_r;
    value_right_out <= right_result_r;

    process (aud_bclk_in, rst_n)
        begin
            if (rst_n = '0') then
                -- Init state (wait_for_input) and init output of FSM
                current_state_r <= wait_for_input;
                left_result_r <= (others => '0');
                right_result_r <= (others => '0');
                shift_r <= (others => '0');
                bit_cnt_r <= 0;
                lrclk_prev_r <= '0';

            -- The MSB of right and left channel are valid on the rising edge of the bit clock

            elsif (aud_bclk_in'event and aud_bclk_in = '1') then
                
                -- The MSB of the left channel is valid on the rising edge of the bit clock
                -- following the rising edge of the word clock
                -- put the MSB into shift register

                if (aud_lrclk_in = '1' and lrclk_prev_r = '0') then
                    current_state_r <= read_left;
                    shift_r <= shift_r(data_width_g-2 downto 0) & aud_data_in;
                    bit_cnt_r <= 1;

                -- The MSB of the right channel is valid on the rising edge of the bit clock
                -- following the falling edge of the word clock
                -- read_right state can only be entered from read_left state so not from wait_for_input
                -- put the MSB into shift register

                elsif (aud_lrclk_in = '0' and lrclk_prev_r = '1' and current_state_r = read_left) then
                    current_state_r <= read_right;
                    shift_r <= shift_r(data_width_g-2 downto 0) & aud_data_in;
                    bit_cnt_r <= 1;

                -- No word clock edges present so stay in current state

                else

                    -- read_left state updates left output
                    
                    if (current_state_r = read_left) then
                        -- When the whole word is put into shift register, update left output of codec model
                        if (bit_cnt_r = data_width_g-1) then
                            left_result_r <= shift_r(data_width_g-2 downto 0) & aud_data_in;
                            bit_cnt_r <= 0;
                        else
                            shift_r <= shift_r(data_width_g-2 downto 0) & aud_data_in;
                            bit_cnt_r <= bit_cnt_r+1;
                        end if;
                    
                    -- read_right state updates right output

                    elsif (current_state_r = read_right) then
                        -- When the whole word is put into shift register, update right output of codec model
                        if (bit_cnt_r = data_width_g-1) then
                            right_result_r <= shift_r(data_width_g-2 downto 0) & aud_data_in;
                            bit_cnt_r <= 0;
                        else
                            shift_r <= shift_r(data_width_g-2 downto 0) & aud_data_in;
                            bit_cnt_r <= bit_cnt_r+1;
                        end if;
                    end if;
                end if;

            lrclk_prev_r <= aud_lrclk_in;

            end if;
    end process;

end rtl;
