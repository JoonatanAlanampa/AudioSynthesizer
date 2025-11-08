library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity adder is
	generic (
		operand_width_g : integer
	);
	port (
		clk, rst_n : in std_logic;
		a_in, b_in : in std_logic_vector(operand_width_g-1 downto 0);
		sum_out : out std_logic_vector(operand_width_g downto 0)
	);
end adder;

architecture rtl of adder is

	signal result : signed(operand_width_g downto 0);
	
begin

	sum_out <= std_logic_vector(result);
	
	process(clk, rst_n)
		begin
			if (rst_n = '0') then
				result <= (others => '0'); -- reset the register
			elsif (clk = '1' and clk'event) then
				result <= resize(signed(a_in), operand_width_g+1) + resize(signed(b_in), operand_width_g+1);
		end if;
	end process;
	
end rtl;


