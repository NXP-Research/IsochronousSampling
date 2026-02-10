-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;
use work.interfaces_msk.all;

entity tb_isochronousSampling_masked is
end entity tb_isochronousSampling_masked;

architecture RTL of tb_isochronousSampling_masked is

	signal clock : std_logic := '0';
	signal reset : std_logic;
	signal start : std_logic;

	constant DEGREE      : natural := 761;
	constant RNG_WIDTH   : natural := 15;
	constant DEGREE_BITS : natural := natural(ceil(log2(real(DEGREE))));
	constant WEIGHT      : natural := 286;

	constant rand_req    : integer := RNG_WIDTH;
	constant rand_blocks : integer := 30;
	constant rand_ceil   : integer := rand_req / rand_blocks + 1;
	signal rnd           : std_logic_vector(rand_ceil * rand_blocks - 1 downto 0);

	signal rng_input       : t_shared(RNG_WIDTH - 1 downto 0)(shares - 1 downto 0);
	signal rng_input_trans : t_shared_trans(shares - 1 downto 0)(RNG_WIDTH - 1 downto 0);

	signal output       : t_shared(1 downto 0)(shares - 1 downto 0);
	signal output_trans : t_shared_trans(shares - 1 downto 0)(1 downto 0);
	signal output_check : std_logic_vector(1 downto 0);
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

	constant RAND_WIDTH_ADDER : integer := get_rand_req(RNG_WIDTH + 1, NUMBER_LEVELS);
	constant RAND_WIDTH_MUX   : natural := and_pini_nrnd * (DEGREE_BITS + 1);
	constant rand_requirement : integer := RAND_WIDTH_ADDER + RAND_WIDTH_MUX;

	signal rand_in   : STD_LOGIC_VECTOR(rand_requirement - 1 downto 0);
	signal rand_full : STD_LOGIC_VECTOR(511 downto 0);
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

		wait for 501 ns;
	end process start_gen;

	IsochronousSampling_masked_inst : entity work.IsochronousSampling_masked
		generic map(
			DEGREE           => DEGREE,
			DEGREE_BITS      => DEGREE_BITS,
			RNG_WIDTH        => RNG_WIDTH,
			WEIGHT           => WEIGHT,
			RAND_WIDTH_ADDER => RAND_WIDTH_ADDER,
			RAND_WIDTH_MUX   => RAND_WIDTH_MUX
		)
		port map(
			clock        => clock,
			reset        => reset,
			start        => start,
			rng_input    => rng_input,
			rand_in      => rand_in,
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
		wait until rising_edge(clock) and enable_rng = '1';
	end process gen_random;

	rng_input_trans(0)                   <= rnd(RNG_WIDTH - 1 downto 0);
	rng_input_trans(shares - 1 downto 1) <= (others => (others => '0'));
	--rng_input_trans(shares - 1 downto 1) <= rng_input_trans(shares - 2 downto 0) when rising_edge(clock);

	rng_input <= t_shared_trans_to_t_shared(rng_input_trans, RNG_WIDTH, shares);

	rand_full <= x"11992233339933333399339933993399119922333399333333993399339933991199223333993333339933993399339911992233339933333399339933993399";

	rand_shift : process(clock) is
	begin
		if rising_edge(clock) then
			if reset = '1' then
				rand_in <= rand_full(rand_requirement - 1 downto 0);
			else
				rand_in <= (not rand_in(rand_requirement - 1 - 7 downto 0)) & ((not rand_in(rand_requirement - 1 downto rand_requirement - 7)) XOR rand_in(6 downto 0));
			end if;
		end if;
	end process rand_shift;

	output_trans <= t_shared_to_t_shared_trans(output, 2, shares);
	
	unmask_output : process (output_trans) is
		variable temp : std_logic_vector(1 downto 0);
		
	begin
		temp := (others => '0');
		for i in 0 to shares-1 loop
			temp := temp XOR output_trans(i);
		end loop;
		
		output_check <= temp;
	end process unmask_output;
	
	check_output : process is
		variable counter : integer := 0;
	begin
		counter := 0;
		wait until start = '1' and rising_edge(clock);

		for i in 0 to DEGREE - 1 loop
			wait until output_valid = '1' and rising_edge(clock);
			if output_check = "00" then
				counter := counter + 1;
			end if;

			polynomial(i)     <= polynomial(i) + to_integer(signed(output_check));
			abs_polynomial(i) <= abs_polynomial(i) + to_integer(abs (signed(output_check)));
		end loop;

		wait until done = '1' and rising_edge(clock);

		assert counter = DEGREE - WEIGHT report "Output weight of polynomial is incorrect: " & integer'image(DEGREE - counter) severity failure;
		report "Output weight of polynomial: " & integer'image(DEGREE - counter) severity note;

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
