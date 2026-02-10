-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;
use work.interfaces_msk.all;

entity tb_RejSamplingMod_masked is
end entity tb_RejSamplingMod_masked;

architecture RTL of tb_RejSamplingMod_masked is
	signal clock : std_logic := '0';
	signal reset : std_logic;
	signal start : std_logic;

	constant DEGREE      : natural := 761;
	constant RNG_WIDTH   : natural := 15;
	constant DEGREE_BITS : natural := natural(ceil(log2(real(DEGREE))));

	constant rand_req    : integer := RNG_WIDTH;
	constant rand_blocks : integer := 30;
	constant rand_ceil   : integer := rand_req / rand_blocks + 1;
	signal rnd           : std_logic_vector(rand_ceil * rand_blocks - 1 downto 0);

	signal rng_input       : t_shared(RNG_WIDTH - 1 downto 0)(shares - 1 downto 0);
	signal rng_input_trans : t_shared_trans(shares - 1 downto 0)(RNG_WIDTH - 1 downto 0);

	signal output       : t_shared(DEGREE_BITS - 1 downto 0)(shares - 1 downto 0);
	signal output_trans : t_shared_trans(shares - 1 downto 0)(DEGREE_BITS - 1 downto 0);
	signal output_check : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal output_valid : std_logic;
	signal done         : std_logic;
	signal enable_rng   : std_logic;

	constant rand_requirement : integer := get_rand_req(RNG_WIDTH + 1, NUMBER_LEVELS);
	signal rand_in            : STD_LOGIC_VECTOR(rand_requirement - 1 downto 0);
	signal rand_full          : STD_LOGIC_VECTOR(511 downto 0);

	signal rejS_to_adder_A     : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal rejS_to_adder_B     : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal rejS_to_adder_valid : std_logic;
	signal rejS_from_adder_S   : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal mult_to_adder_A     : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal mult_to_adder_B     : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal mult_to_adder_valid : std_logic;
	signal mult_from_adder_S   : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);

	signal adder_input_A  : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal adder_input_B  : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal adder_output_S : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
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

	RejSamplingMod_masked_inst : entity work.RejSamplingMod_masked
		generic map(
			DEGREE      => DEGREE,
			DEGREE_BITS => DEGREE_BITS,
			RNG_WIDTH   => RNG_WIDTH
		)
		port map(
			clock               => clock,
			reset               => reset,
			start               => start,
			rng_input           => rng_input,
			enable_rng          => enable_rng,
			output              => output,
			output_valid        => output_valid,
			done                => done,
			rejS_to_adder_A     => rejS_to_adder_A,
			rejS_to_adder_B     => rejS_to_adder_B,
			rejS_to_adder_valid => rejS_to_adder_valid,
			rejS_from_adder_S   => rejS_from_adder_S,
			mult_to_adder_A     => mult_to_adder_A,
			mult_to_adder_B     => mult_to_adder_B,
			mult_to_adder_valid => mult_to_adder_valid,
			mult_from_adder_S   => mult_from_adder_S
		);

	ska_16_inst : entity work.ska_16
		generic map(
			width                  => RNG_WIDTH + 1,
			level_rand_requirement => rand_requirement
		)
		port map(
			clk     => clock,
			A       => adder_input_A,
			B       => adder_input_B,
			rand_in => rand_in,
			S       => adder_output_S
		);

	adder_input_A <= rejS_to_adder_A when rejS_to_adder_valid = '1' else mult_to_adder_A when mult_to_adder_valid = '1' else (others => (others => '0'))  after 0.1 ns;
	adder_input_B <= rejS_to_adder_B when rejS_to_adder_valid = '1' else mult_to_adder_B when mult_to_adder_valid = '1' else (others => (others => '0')) after 0.1 ns;
	
	rejS_from_adder_S <= adder_output_S after 0.1 ns;
	mult_from_adder_S <= adder_output_S after 0.1 ns;

	output_trans <= t_shared_to_t_shared_trans(output, DEGREE_BITS, shares);
	output_check <= output_trans(0) XOR output_trans(1);

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

	rng_input_trans(0)                   <= rnd(RNG_WIDTH - 1 downto 0);
	rng_input_trans(shares - 1 downto 1) <= (others => (others => '0'));

	rng_input <= t_shared_trans_to_t_shared(rng_input_trans, RNG_WIDTH, shares);

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
