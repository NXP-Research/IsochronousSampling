-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.interfaces_msk.all;

entity tb_iterative_masked_multiplier is
end entity tb_iterative_masked_multiplier;

architecture RTL of tb_iterative_masked_multiplier is
	signal clock : std_logic := '0';
	signal reset : std_logic;
	signal start : std_logic;

	constant WIDTH_A : natural := 15;
	constant WIDTH_B : natural := 10;

	signal output_unmasked : unsigned(WIDTH_A + WIDTH_B - 1 downto 0);
	signal output_valid    : std_logic;

	signal input_A_unmasked : unsigned(WIDTH_A - 1 downto 0);
	signal input_B          : unsigned(WIDTH_B - 1 downto 0);

	signal input_A       : t_shared(WIDTH_A - 1 downto 0)(shares - 1 downto 0);
	signal input_A_trans : t_shared_trans(shares - 1 downto 0)(WIDTH_A - 1 downto 0);
	signal output        : t_shared(WIDTH_A + WIDTH_B - 1 downto 0)(shares - 1 downto 0);
	signal output_trans  : t_shared_trans(shares - 1 downto 0)(WIDTH_A + WIDTH_B - 1 downto 0);

	constant rand_requirement : integer := get_rand_req(WIDTH_A + 1, NUMBER_LEVELS);
	signal rand_in            : STD_LOGIC_VECTOR(rand_requirement - 1 downto 0);
	signal rand_full          : STD_LOGIC_VECTOR(511 downto 0);

	signal to_adder_A     : t_shared(WIDTH_A downto 0)(shares - 1 downto 0);
	signal to_adder_B     : t_shared(WIDTH_A downto 0)(shares - 1 downto 0);
	signal to_adder_valid : std_logic;
	signal from_adder_S   : t_shared(WIDTH_A downto 0)(shares - 1 downto 0);
	signal adder_input_A  : t_shared(WIDTH_A downto 0)(shares - 1 downto 0);
	signal adder_input_B  : t_shared(WIDTH_A downto 0)(shares - 1 downto 0);
	signal adder_output_S : t_shared(WIDTH_A downto 0)(shares - 1 downto 0);

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
		start            <= '0';
		wait for 201 ns;
		start            <= '1';
		input_A_unmasked <= to_unsigned(100, WIDTH_A);
		input_B          <= to_unsigned(31, WIDTH_B);
		wait for 1 ns;
		wait until rising_edge(clock);
		start            <= '0';
		wait until output_valid = '1' and rising_edge(clock);

		wait for 201 ns;
		start            <= '1';
		input_A_unmasked <= to_unsigned(2**16 - 3, WIDTH_A);
		input_B          <= to_unsigned(253, WIDTH_B);
		wait for 1 ns;
		wait until rising_edge(clock);
		start            <= '0';
		wait until output_valid = '1' and rising_edge(clock);

		wait for 201 ns;
		start            <= '1';
		input_A_unmasked <= to_unsigned(2**16 - 1, WIDTH_A);
		input_B          <= to_unsigned(2**10 - 1, WIDTH_B);
		wait for 1 ns;
		wait until rising_edge(clock);
		start            <= '0';
		wait until output_valid = '1' and rising_edge(clock);
	end process start_gen;

	input_A_trans(0)                   <= std_logic_vector(input_A_unmasked);
	input_A_trans(shares - 1 downto 1) <= (others => (others => '0'));

	input_A <= t_shared_trans_to_t_shared(input_A_trans, WIDTH_A, shares);

	output_trans <= t_shared_to_t_shared_trans(output, WIDTH_A + WIDTH_B, shares);

	output_unmasked <= unsigned(output_trans(0) XOR output_trans(1));

	iterative_masked_multiplier_inst : entity work.iterative_masked_multiplier
		generic map(
			WIDTH_A    => WIDTH_A,
			WIDTH_B    => WIDTH_B
		)
		port map(
			clock          => clock,
			reset          => reset,
			start          => start,
			input_A        => input_A,
			input_B        => input_B,
			to_adder_A     => to_adder_A,
			to_adder_B     => to_adder_B,
			to_adder_valid => to_adder_valid,
			from_adder_S   => from_adder_S,
			output         => output,
			output_valid   => output_valid
		);

	ska_16_inst : entity work.ska_16
		generic map(
			width                  => WIDTH_A + 1,
			level_rand_requirement => rand_requirement
		)
		port map(
			clk     => clock,
			A       => adder_input_A,
			B       => adder_input_B,
			rand_in => rand_in,
			S       => adder_output_S
		);

	adder_input_A <= to_adder_A after 0.1 ns;
	adder_input_B <= to_adder_B after 0.1 ns;
	from_adder_S <= adder_output_S after 0.1 ns;
	
	rand_full <= x"11992233339933333399339933993399119922333399333333993399339933991199223333993333339933993399339911992233339933333399339933993399";

	rand_shift : process(clock) is
	begin
		if rising_edge(clock) then
			if reset = '1' then
				rand_in <= rand_full(rand_requirement - 1 downto 0);
			else
				rand_in <= (not rand_in(rand_requirement - 1 - 8 downto 0)) & (not rand_in(rand_requirement - 1 downto rand_requirement - 8));
			end if;
		end if;
	end process rand_shift;
end architecture RTL;
