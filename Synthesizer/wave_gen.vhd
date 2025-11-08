library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity wave_gen is
    generic (
        width_g : integer;
        step_g  : integer
    );
    port (
        clk : in std_logic;
        rst_n : in std_logic;
        sync_clear_n_in : in std_logic;
        value_out : out std_logic_vector(width_g-1 downto 0)
    );
end wave_gen;

architecture rtl of wave_gen is

    constant max_c : integer := ((2**(width_g-1)-1)/step_g)*step_g;
    constant min_c : integer := -max_c;

    signal result_r : signed(width_g-1 downto 0);
    signal direction : std_logic := '1'; 

begin

    value_out <= std_logic_vector(result_r);

    -- process to create the waveform

    process(clk, rst_n)
        begin
            if (rst_n = '0') then -- reset
                result_r <= (others => '0');
                direction <= '1';
            elsif (clk'event and clk = '1') then -- synchronous
                if (sync_clear_n_in = '0') then -- shut off generator
                    result_r <= (others => '0');
                    direction <= '1';
                else
                    if (result_r = to_signed(max_c, width_g)) then -- upper limit behaviour
                        result_r <= result_r - to_signed(step_g, width_g);
                        direction <= '0';
                    elsif (result_r = to_signed(min_c, width_g)) then -- lower limit behaviour
                        result_r <= result_r + to_signed(step_g, width_g);
                        direction <= '1';
                    elsif (direction = '1') then -- signal in upwards transition
                        result_r <= result_r + to_signed(step_g, width_g);
                    elsif (direction = '0') then -- signal in downwards transition
                        result_r <= result_r - to_signed(step_g, width_g);
                end if;
            end if;
        end if;
    end process;


end rtl;
