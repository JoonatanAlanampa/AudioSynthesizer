library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;
use std.textio.all;

entity tb_multi_port_adder is
    generic (
        operand_width_g : integer := 3
    );
end tb_multi_port_adder;

architecture testbench of tb_multi_port_adder is

    -- component multi_port_adder introduction
    component multi_port_adder is
        generic (
            operand_width_g     : integer := 16;
            num_of_operands_g   : integer := 4
        );
        port (
            clk         : in std_logic;
            rst_n       : in std_logic;
            operands_in : in std_logic_vector(operand_width_g*num_of_operands_g-1 downto 0);
            sum_out     : out std_logic_vector(operand_width_g-1 downto 0)
        );
    end component;

    constant period_c : time := 10 ns;
    constant num_of_operands_c : integer := 4;
    constant duv_delay_c : integer := 2;

    signal clk : std_logic := '0';
    signal rst_n : std_logic := '0';
    signal operands_r : std_logic_vector(operand_width_g*num_of_operands_c-1 downto 0);
    signal sum : std_logic_vector(operand_width_g-1 downto 0);
    signal output_valid_r : std_logic_vector(duv_delay_c+1-1 downto 0);

    -- files and their correct syntax AND correct paths
    file input_f : text open read_mode is "input.txt";
    file ref_results_f : text open read_mode is "ref_results.txt";
    file output_f : text open write_mode is "output.txt";

begin

    clk <= not clk after period_c/2;
    rst_n <= '1' after 4*period_c;

    -- component instantiation
    multi_port_adder_1 : multi_port_adder
    generic map (
        operand_width_g     => operand_width_g,
        num_of_operands_g   => num_of_operands_c
    )
    port map (
        clk         => clk,
        rst_n       => rst_n,
        operands_in => operands_r,
        sum_out     => sum
    );

    -- input reader
    input_reader : process(clk, rst_n)
        type values is array (num_of_operands_c-1 downto 0) of integer;
        variable line_v : line;
        variable value_v : values;
    begin
        if (rst_n = '0') then -- active low reset for registered signals
            operands_r <= (others => '0');
            output_valid_r <= (others => '0');
        elsif (clk = '1' and clk'event) then -- rising clock edge 
            output_valid_r <= output_valid_r(duv_delay_c-1 downto 0) & '1'; -- add lsb 1 and shift to left by cutting msb
            if not (endfile(input_f)) then -- check EOF condition
                readline(input_f, line_v); -- read line from input file
                for i in value_v'range loop -- loop through values on line
                    read(line_v, value_v(i)); -- read values on line
                    operands_r(((i+1)*operand_width_g-1) downto operand_width_g*i) <= std_logic_vector(to_signed(value_v(i), operand_width_g)); -- assign correct value to multiport adders inputs via signal operands_r
                end loop;
            end if;
        end if;
    end process;

    -- checker
    checker : process(clk)
        variable line_v : line;
        variable value_v : integer;
    begin
        if (clk = '1' and clk'event) then
            if (output_valid_r(output_valid_r'left) = '1') then -- check if MSB of output_valid_r is 1
                if not(endfile(ref_results_f)) then
                    readline(ref_results_f, line_v); -- read line from reference 
                    read(line_v, value_v); -- read value from line

                    assert value_v = to_integer(signed(sum)) report "Reference and read value do not match" severity failure; -- catch error
                    
                    write(line_v, to_integer(signed(sum))); -- write DUVs output value to line
                    writeline(output_f, line_v); -- write line to output file
                else
                    assert false report "Simulation done" severity failure; -- inform successful simulation
                end if;
            end if;
        end if;
    end process;

end testbench;
