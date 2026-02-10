-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

-- Generic simple dual port, single clock RAM
entity SDP_RAM is
	Generic(
		ADDRESS_WIDTH : integer := 8;
		DATA_WIDTH    : integer := 8
	);
	Port(clock      : in  std_logic;
	     address_a  : in  std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
	     data_out_a : out std_logic_vector(DATA_WIDTH - 1 downto 0);
	     address_b  : in  std_logic_vector(ADDRESS_WIDTH - 1 downto 0);
	     write_b    : in  std_logic;
	     data_in_b  : in  std_logic_vector(DATA_WIDTH - 1 downto 0)
	    );
end entity SDP_RAM; 


architecture RTL of SDP_RAM is
	type memory_type is array (0 to (2**ADDRESS_WIDTH) - 1) of std_logic_vector(DATA_WIDTH - 1 downto 0);

	shared variable RAM : memory_type;
begin

	port_a : process(clock) is
	begin
		if rising_edge(clock) then
			data_out_a <= RAM(to_integer(unsigned(address_a)));
		end if;
	end process port_a;

	port_b : process(clock) is
	begin
		if rising_edge(clock) then
			if (write_b = '1') then
				RAM(to_integer(unsigned(address_b))) := data_in_b;
			end if;
		end if;
	end process port_b;
end architecture RTL;
