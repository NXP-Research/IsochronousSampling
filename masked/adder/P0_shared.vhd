--
-- Copyright (c) 2021 Florian Bache and Tim Güneysu
-- Copyright (c) 2023 Adrian Marotzke, Georg Land, Jan Richter-Brockmann
--
-- SPDX-License-Identifier: MIT
--


library IEEE;
use IEEE.STD_LOGIC_1164.ALL;

-- Uncomment the following library declaration if using
-- arithmetic functions with Signed or Unsigned values
--use IEEE.NUMERIC_STD.ALL;

-- Uncomment the following library declaration if instantiating
-- any Xilinx primitives in this code.
--library UNISIM;
--use UNISIM.VComponents.all;

use work.interfaces_msk.all;

entity P0_shared is
    Port ( 
		     --clk : in STD_LOGIC;
			  A : in  t_shared_bit;
           B : in  t_shared_bit;
			  --rand: in t_rand;
           G : out  t_shared_bit);
end P0_shared;



--architecture unmasked of P0_shared is
--
--
--begin
--G(0 downto 0)<= A(0 downto 0) xor B(0 downto 0);
--end unmasked;


architecture masked of P0_shared is

COMPONENT MSKxor
	generic (d: integer:=2);
	PORT(
		ina : IN t_shared_bit;
		inb : IN t_shared_bit;          
		out_c : OUT t_shared_bit
		);
	END COMPONENT;

begin
--G<= A and B;


Inst_MSKxor: MSKxor generic map (d => shares)
	PORT MAP(
		ina => a,
		inb => b,
		out_c => G
	);

end masked;

