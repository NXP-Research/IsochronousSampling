-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;

entity tb_RejSamplingMod is
end entity tb_RejSamplingMod;

architecture RTL of tb_RejSamplingMod is
	signal clock : std_logic := '0';
	signal reset : std_logic;
	signal start : std_logic;

	constant DEGREE      : natural := 761;
	constant RNG_WIDTH   : natural := 16;
	constant DEGREE_BITS : natural := natural(ceil(log2(real(DEGREE))));

	constant rand_req    : integer := RNG_WIDTH;
	constant rand_blocks : integer := 30;
	constant rand_ceil   : integer := rand_req / rand_blocks + 1;
	signal rnd           : std_logic_vector(rand_ceil * rand_blocks - 1 downto 0);

	signal rng_input : std_logic_vector(RNG_WIDTH - 1 downto 0);

	signal output       : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal output_valid : std_logic;
	signal done         : std_logic;
	signal enable_rng : std_logic;
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
		start <= '0';
		wait for 201 ns;
		start <= '1';
		wait until rising_edge(clock);
		start <= '0';
		wait;
	end process start_gen;

	RejSamplingMod_inst : entity work.RejSamplingMod
		generic map(
			DEGREE      => DEGREE,
			DEGREE_BITS => DEGREE_BITS,
			RNG_WIDTH   => RNG_WIDTH
		)
		port map(
			clock        => clock,
			reset        => reset,
			start        => start,
			rng_input    => rng_input,
			enable_rng   => enable_rng,
			output       => output,
			output_valid => output_valid,
			done         => done
		);

	gen_random : process is
		variable seed1         : positive := 1;
		variable seed2         : positive := 1;
		variable rand          : real;
		constant range_of_rand : real     := (2.0)**(rand_blocks) - 1.0;
	begin
		uniform(seed1, seed2, rand);

		for i in 0 to rand_req / rand_blocks loop
			rnd((i + 1) * rand_blocks - 1 downto (i) * rand_blocks) <= std_logic_vector(to_unsigned(integer(rand * range_of_rand), rand_blocks));
		end loop;

		--rnd_input <= (others => '0');
		wait until rising_edge(clock);
	end process gen_random;

	rng_input <= rnd(RNG_WIDTH - 1 downto 0);
end architecture RTL;
