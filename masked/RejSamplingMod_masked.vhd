-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;
use work.interfaces_msk.all;

entity RejSamplingMod_masked is
	generic(
		DEGREE      : natural := 761;
		DEGREE_BITS : natural := 10;
		RNG_WIDTH   : natural := 15
	);
	port(
		clock               : in  std_logic;
		reset               : in  std_logic;
		start               : in  std_logic;
		rng_input           : in  t_shared(RNG_WIDTH - 1 downto 0)(shares - 1 downto 0);
		enable_rng          : out std_logic;
		output              : out t_shared(DEGREE_BITS - 1 downto 0)(shares - 1 downto 0);
		output_valid        : out std_logic;
		output_enable       : in  std_logic;
		done                : out std_logic;
		rejS_to_adder_A     : out t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
		rejS_to_adder_B     : out t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
		rejS_to_adder_valid : out std_logic;
		rejS_from_adder_S   : in  t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
		mult_to_adder_A     : out t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
		mult_to_adder_B     : out t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
		mult_to_adder_valid : out std_logic;
		mult_from_adder_S   : in  t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0)
	);
end entity RejSamplingMod_masked;

architecture RTL of RejSamplingMod_masked is
	type pre_array_type is array (0 to DEGREE - 1) of unsigned(RNG_WIDTH downto 0);

	function compute_pre_array(L : natural; n : natural)
	return pre_array_type is
		variable pre_array_temp : pre_array_type               := (others => (others => '0'));
		constant two_power_L    : unsigned(RNG_WIDTH downto 0) := to_unsigned(2**L, RNG_WIDTH + 1);
	begin
		for i in 0 to n - 1 loop
			pre_array_temp(i) := two_power_L mod (n - i);
		end loop;

		return pre_array_temp;
	end function compute_pre_array;

	constant pre_array : pre_array_type := compute_pre_array(RNG_WIDTH, DEGREE);

	type state_type is (IDLE, START_PIPE, RUNNING_MULT, CHECK_VALID, WRITE_RAM, OUTPUT_SAMPLES, COMPLETE);
	signal state_rejmod : state_type := IDLE;

	signal x : t_shared(RNG_WIDTH - 1 downto 0)(shares - 1 downto 0);
	signal s : unsigned(DEGREE_BITS - 1 downto 0);

	signal m : t_shared(RNG_WIDTH + DEGREE_BITS - 1 downto 0)(shares - 1 downto 0);

	signal m_mod_l : t_shared(RNG_WIDTH - 1 downto 0)(shares - 1 downto 0);
	signal m_div2l : t_shared(DEGREE_BITS - 1 downto 0)(shares - 1 downto 0);

	signal counter      : integer range 0 to DEGREE;
	signal counter_wait : integer range 0 to 15;

	signal valid_sample : std_logic;

	--	signal si_address_a  : std_logic_vector(DEGREE_BITS - 1 downto 0);
	--	signal si_data_out_a : t_shared_trans(shares - 1 downto 0)(DEGREE_BITS - 1 downto 0);
	--	signal si_address_b  : std_logic_vector(DEGREE_BITS - 1 downto 0);
	--	signal si_write_b    : std_logic;
	--	signal si_data_in_b  : t_shared_trans(shares - 1 downto 0)(DEGREE_BITS - 1 downto 0);

	signal mult_start        : std_logic;
	signal mult_input_A      : t_shared(RNG_WIDTH - 1 downto 0)(shares - 1 downto 0);
	signal mult_input_B      : unsigned(DEGREE_BITS - 1 downto 0);
	signal mult_output       : t_shared(RNG_WIDTH + DEGREE_BITS - 1 downto 0)(shares - 1 downto 0);
	signal mult_output_valid : std_logic;

	signal added_input_A  : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal added_input_B  : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal added_output_S : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);

	signal t_array_counter : t_shared_trans(shares - 1 downto 0)(RNG_WIDTH downto 0);

begin
	fsm_process : process(clock, reset) is
		variable temp : std_logic;
	begin
		if reset = '1' then
			state_rejmod <= IDLE;
			done         <= '0';
			--output_valid <= '0';
			enable_rng   <= '0';
			valid_sample <= '0';

			mult_start <= '0';

			rejS_to_adder_valid <= '0';
		elsif rising_edge(clock) then
			case state_rejmod is
				when IDLE =>
					if start = '1' then
						state_rejmod <= START_PIPE;
						enable_rng   <= '1';
					end if;

					counter <= 0;
					done    <= '0';
				when START_PIPE =>
					x          <= rng_input;
					s          <= to_unsigned(DEGREE - counter, DEGREE_BITS);
					mult_start <= '1';

					state_rejmod <= RUNNING_MULT;

					enable_rng <= '0';

				when RUNNING_MULT =>
					mult_start <= '0';

					if mult_output_valid = '1' then
						state_rejmod                          <= CHECK_VALID;
						added_input_A(RNG_WIDTH)              <= (others => '0');
						added_input_A(RNG_WIDTH - 1 downto 0) <= m_mod_l;
						added_input_B                         <= t_shared_trans_to_t_shared(t_array_counter, RNG_WIDTH + 1, shares);
						rejS_to_adder_valid                   <= '1';
						counter_wait                          <= 0;
					end if;
				when CHECK_VALID =>
					rejS_to_adder_valid <= '0';

					counter_wait <= counter_wait + 1;
					if counter_wait = 10 then
						temp := '0';

						-- unmask the highest bit of adder output
						for j in 0 to shares - 1 loop
							temp := temp XOR added_output_S(RNG_WIDTH)(j);
						end loop;

						-- if the highest bit is 0, then the output is positive, which means m_mod_l >= pre_array(counter)
						temp         := not temp;
						valid_sample <= temp;

						if temp = '1' then
							state_rejmod <= WRITE_RAM;
						else
							state_rejmod <= START_PIPE;
							enable_rng   <= '1';
						end if;
					end if;
				when WRITE_RAM =>
					if output_enable = '1' then
						counter      <= counter + 1;
						state_rejmod <= START_PIPE;
						enable_rng   <= '1';
						valid_sample <= '0';

						if counter = DEGREE - 1 then
							state_rejmod <= COMPLETE;

							enable_rng <= '0';
							counter    <= 0;
							--counter_wait <= 15;
						end if;
					end if;
				when OUTPUT_SAMPLES =>
					--output_valid <= '0';
					counter_wait <= counter_wait + 1;

					if counter_wait = 15 then
						counter_wait <= 0;

						counter <= counter + 1;
						if counter = DEGREE - 1 then
							state_rejmod <= COMPLETE;
							counter      <= 0;
						end if;

						--output_valid <= '1';
					end if;

				when COMPLETE =>
					state_rejmod <= IDLE;
					done         <= '1';

					counter_wait <= 0;
					--output_valid <= '0';
			end case;

		end if;
	end process fsm_process;

	mult_input_A <= x;
	mult_input_B <= s;

	m       <= mult_output;
	m_mod_l <= m(RNG_WIDTH - 1 downto 0);
	m_div2l <= m(RNG_WIDTH + DEGREE_BITS - 1 downto RNG_WIDTH) when rising_edge(clock) and mult_output_valid = '1';

	t_array_counter(0)                   <= std_logic_vector((NOT pre_array(counter)) + 1);
	t_array_counter(shares - 1 downto 1) <= (others => (others => '0'));

	--	si_address_b <= std_logic_vector(to_unsigned(counter, DEGREE_BITS));
	--	--si_data_in_b <= std_logic_vector(shift_right(m, RNG_WIDTH)(DEGREE_BITS - 1 downto 0));
	--	si_data_in_b <= t_shared_to_t_shared_trans(m_div2l, DEGREE_BITS, shares);
	--	si_write_b   <= valid_sample;
	--
	--	si_address_a <= std_logic_vector(to_unsigned(counter, DEGREE_BITS));
	--	output       <= t_shared_trans_to_t_shared(si_data_out_a, DEGREE_BITS, shares);

	output_process : process(clock, reset) is
	begin
		if reset = '1' then
			output_valid <= '0';
		elsif rising_edge(clock) then
			if output_enable = '1' then
				output       <= m_div2l;
				output_valid <= valid_sample;
			end if;

		end if;
	end process output_process;

	iterative_masked_multiplier_inst : entity work.iterative_masked_multiplier
		generic map(
			WIDTH_A => RNG_WIDTH,
			WIDTH_B => DEGREE_BITS
		)
		port map(
			clock          => clock,
			reset          => reset,
			start          => mult_start,
			input_A        => mult_input_A,
			input_B        => mult_input_B,
			to_adder_A     => mult_to_adder_A,
			to_adder_B     => mult_to_adder_B,
			to_adder_valid => mult_to_adder_valid,
			from_adder_S   => mult_from_adder_S,
			output         => mult_output,
			output_valid   => mult_output_valid
		);

	rejS_to_adder_A <= added_input_A;
	rejS_to_adder_B <= added_input_B;
	added_output_S  <= rejS_from_adder_S;

	--	gen_sdp_msk_ram : for i in 0 to shares - 1 generate
	--		SDP_dist_RAM_inst : entity work.SDP_dist_RAM
	--			generic map(
	--				ADDRESS_WIDTH => DEGREE_BITS,
	--				DATA_WIDTH    => DEGREE_BITS
	--			)
	--			port map(
	--				clock      => clock,
	--				address_a  => si_address_a,
	--				data_out_a => si_data_out_a(i),
	--				address_b  => si_address_b,
	--				write_b    => si_write_b,
	--				data_in_b  => si_data_in_b(i)
	--			);
	--	end generate gen_sdp_msk_ram;

end architecture RTL;
