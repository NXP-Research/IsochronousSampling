-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;

entity tb_isochronousSampling_LW_NTRUHPS is
end entity tb_isochronousSampling_LW_NTRUHPS;

architecture RTL of tb_isochronousSampling_LW_NTRUHPS is

	signal clock : std_logic := '0';
	signal reset : std_logic;
	signal start : std_logic;

	constant DEGREE      : natural := 821;
	constant RNG_WIDTH   : natural := 16;
	constant DEGREE_BITS : natural := natural(ceil(log2(real(DEGREE))));
	constant WEIGHT      : natural := 510;

	constant rand_req    : integer := RNG_WIDTH;
	constant rand_blocks : integer := 30;
	constant rand_ceil   : integer := rand_req / rand_blocks + 1;
	signal rnd           : std_logic_vector(rand_ceil * rand_blocks - 1 downto 0);

	signal rng_input : std_logic_vector(RNG_WIDTH - 1 downto 0);

	signal output       : std_logic_vector(1 downto 0);
	signal output_valid : std_logic;
	signal done         : std_logic;
	signal enable_rng   : std_logic;

	type integer_array_type is array (DEGREE - 1 downto 0) of integer;

	signal abs_polynomial : integer_array_type := (others => 0);
	signal polynomial     : integer_array_type := (others => 0);

	signal max_abs : integer := 0;
	signal min_abs : integer := 0;

	signal max_poly : integer := 0;
	signal min_poly : integer := 0;

	function find_max(poly_input : integer_array_type)
	return integer is
		variable max : integer := poly_input(0);

	begin
		for i in poly_input'range loop
			if max < poly_input(i) then
				max := poly_input(i);
			end if;
		end loop;
		return max;
	end function find_max;

	function find_min(poly_input : integer_array_type)
	return integer is
		variable min : integer := poly_input(0);

	begin
		for i in poly_input'range loop
			if min > poly_input(i) then
				min := poly_input(i);
			end if;
		end loop;
		return min;
	end function find_min;

	signal cycle_counter : integer := 0;
	signal runs          : integer := 0;
	signal avg_cycles    : real    := 0.0;

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
		wait for 1 ns;
		wait until rising_edge(clock);
		start <= '0';
		wait until done = '1' and rising_edge(clock);
	end process start_gen;

	IsochronousSampling_inst : entity work.IsochronousSampling_NTRUHPS_LW
		generic map(
			DEGREE      => DEGREE,
			DEGREE_BITS => DEGREE_BITS,
			RNG_WIDTH   => RNG_WIDTH,
			WEIGHT      => WEIGHT
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
		variable seed1 : positive := 1;
		variable seed2 : positive := 1;
		variable rand  : real;
	begin
		uniform(seed1, seed2, rand);

		for i in rnd'range loop
			uniform(seed1, seed2, rand);

			if rand >= 0.5 then
				rnd(i) <= '1';
			else
				rnd(i) <= '0';
			end if;

		end loop;

		--rnd_input <= (others => '0');
		wait until rising_edge(clock);
	end process gen_random;

	rng_input <= rnd(RNG_WIDTH - 1 downto 0) when enable_rng = '1' else (others => '0');

	check_output : process is
		variable counter : integer := 0;
	begin
		counter := 0;
		wait until start = '1' and rising_edge(clock);

		for i in 0 to DEGREE - 1 loop
			wait until output_valid = '1' and rising_edge(clock);
			if output = "00" then
				counter := counter + 1;
			end if;

			polynomial(i)     <= polynomial(i) + to_integer(signed(output));
			abs_polynomial(i) <= abs_polynomial(i) + to_integer(abs (signed(output)));
		end loop;

		wait until done = '1' and rising_edge(clock);

		assert counter = DEGREE - WEIGHT report "Output weight of polynomial is incorrect: " & integer'image(DEGREE - counter) severity error;

	end process check_output;

	check_min_max : process is
	begin
		wait until done = '1' and rising_edge(clock);

		max_abs <= find_max(abs_polynomial);
		min_abs <= find_min(abs_polynomial);

		max_poly <= find_max(polynomial);
		min_poly <= find_min(polynomial);
	end process check_min_max;

	count_cycles : process is
	begin
		wait until start = '1' and rising_edge(clock);

		while rising_edge(clock) and done /= '1' loop
			wait until rising_edge(clock);
			cycle_counter <= cycle_counter + 1;
		end loop;

		runs <= runs + 1;

	end process count_cycles;

	avg_cycles <= real(cycle_counter) / real(runs) when runs /= 0 and rising_edge(clock) and start = '1';
end architecture RTL;
