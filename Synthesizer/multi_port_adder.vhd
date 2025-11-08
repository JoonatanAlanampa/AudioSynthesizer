-- libraries
library ieee;
use ieee.std_logic_1164.all;

-- entity
entity multi_port_adder is
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
end multi_port_adder;

architecture structural of multi_port_adder is

    -- component adder introduction
    component adder is
        generic (
            operand_width_g : integer
        );
        port (
            clk, rst_n  : in std_logic;
            a_in, b_in  : in std_logic_vector(operand_width_g-1 downto 0);
            sum_out 	: out std_logic_vector(operand_width_g downto 0)
        );
    end component;

    -- signals and their wanted type
    type arrays is array (num_of_operands_g/2-1 downto 0) of std_logic_vector(operand_width_g+1-1 downto 0);
    signal subtotal : arrays;
    signal total : std_logic_vector(operand_width_g+2-1 downto 0);

begin

    -- component instantiations
    adder_1 : adder
    generic map (
        operand_width_g => operand_width_g
    )
    port map (
        clk     => clk,
        rst_n   => rst_n,
        a_in    => operands_in(operand_width_g-1 downto 0), -- operands_in split into 4, first part
        b_in    => operands_in(2*operand_width_g-1 downto operand_width_g), -- operands_in split into 4, second part
        sum_out => subtotal(0)
    );

    adder_2 : adder
    generic map (
        operand_width_g => operand_width_g
    )
    port map ( 
        clk     => clk,
        rst_n   => rst_n,
        a_in    => operands_in(3*operand_width_g-1 downto 2*operand_width_g), -- operands_in split into 4, third part
        b_in    => operands_in(4*operand_width_g-1 downto 3*operand_width_g), -- operands_in split into 4, fourth part
        sum_out => subtotal(1)
    );

    adder_3 : adder
    generic map (
        operand_width_g => operand_width_g+1
    )
    port map (
        clk     => clk,
        rst_n   => rst_n,
        a_in    => subtotal(0), 
        b_in    => subtotal(1),
        sum_out => total
    );

    sum_out <= total(operand_width_g-1 downto 0);

    assert num_of_operands_g = 4 report "num_of_operands_g wrong" severity failure;

end structural;
