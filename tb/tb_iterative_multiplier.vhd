-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

entity tb_iterative_multiplier is
end entity tb_iterative_multiplier;

architecture RTL of tb_iterative_multiplier is
	signal clock : std_logic := '0';
	signal reset : std_logic;
	signal start : std_logic;

	constant WIDTH_A : natural := 16;
	constant WIDTH_B : natural := 10;

	signal output       : unsigned(WIDTH_A + WIDTH_B - 1 downto 0);
	signal output_valid : std_logic;

	signal input_A : unsigned(WIDTH_A - 1 downto 0);
	signal input_B : unsigned(WIDTH_B - 1 downto 0);
begin

	clock_gen : process is
	begin
		clock <= not clock;
		wait for 2 ns;
	end process clock_gen;

	reset_gen : process is
	begin
		reset <= '1';
		wait for 100 ns;
		reset <= '0';
		wait;
	end process reset_gen;

	start_gen : process is
	begin
		start   <= '0';
		wait for 201 ns;
		start   <= '1';
		input_A <= to_unsigned(100, WIDTH_A);
		input_B <= to_unsigned(31, WIDTH_B);
		wait for 1 ns;
		wait until rising_edge(clock);
		start   <= '0';
		wait until output_valid = '1' and rising_edge(clock);

		wait for 201 ns;
		start   <= '1';
		input_A <= to_unsigned(2**16 - 3, WIDTH_A);
		input_B <= to_unsigned(253, WIDTH_B);
		wait for 1 ns;
		wait until rising_edge(clock);
		start   <= '0';
		wait until output_valid = '1' and rising_edge(clock);

		wait for 201 ns;
		start   <= '1';
		input_A <= to_unsigned(2**16 - 1, WIDTH_A);
		input_B <= to_unsigned(2**10 - 1, WIDTH_B);
		wait for 1 ns;
		wait until rising_edge(clock);
		start   <= '0';
		wait until output_valid = '1' and rising_edge(clock);
	end process start_gen;

	iterative_multiplier_inst : entity work.iterative_multiplier
		generic map(
			WIDTH_A => WIDTH_A,
			WIDTH_B => WIDTH_B
		)
		port map(
			clock        => clock,
			reset        => reset,
			start        => start,
			input_A      => input_A,
			input_B      => input_B,
			output       => output,
			output_valid => output_valid
		);

end architecture RTL;
