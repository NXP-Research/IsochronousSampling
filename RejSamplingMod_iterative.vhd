-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;

entity RejSamplingMod_Iterative is
	generic(
		DEGREE      : natural := 761;
		DEGREE_BITS : natural := 10;
		RNG_WIDTH   : natural := 16
	);
	port(
		clock        : in  std_logic;
		reset        : in  std_logic;
		start        : in  std_logic;
		rng_input    : in  std_logic_vector(RNG_WIDTH - 1 downto 0);
		enable_rng   : out std_logic;
		output       : out std_logic_vector(DEGREE_BITS - 1 downto 0);
		output_valid : out std_logic;
		done         : out std_logic
	);
end entity RejSamplingMod_Iterative;

architecture RTL of RejSamplingMod_Iterative is
	type t_array_type is array (0 to DEGREE - 1) of unsigned(RNG_WIDTH downto 0);

	function compute_t_array(L : natural; n : natural)
	return t_array_type is
		variable t_array_temp : t_array_type                 := (others => (others => '0'));
		constant two_power_L  : unsigned(RNG_WIDTH downto 0) := to_unsigned(2**L, RNG_WIDTH + 1);
	begin
		for i in 0 to n - 1 loop
			t_array_temp(i) := two_power_L mod (n - i);
		end loop;

		return t_array_temp;
	end function compute_t_array;

	constant t_array : t_array_type := compute_t_array(RNG_WIDTH, DEGREE);

	type state_type is (IDLE, START_PIPE, RUNNING, OUTPUT_SAMPLES, COMPLETE);
	signal state_rejmod : state_type := IDLE;

	signal x : unsigned(RNG_WIDTH - 1 downto 0);
	signal s : unsigned(DEGREE_BITS - 1 downto 0);

	signal m : unsigned(RNG_WIDTH + DEGREE_BITS - 1 downto 0);

	signal m_mod_l : unsigned(RNG_WIDTH - 1 downto 0);

	signal counter : integer range 0 to DEGREE;

	signal valid_sample   : std_logic;

	signal si_address_a  : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal si_data_out_a : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal si_address_b  : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal si_write_b    : std_logic;
	signal si_data_in_b  : std_logic_vector(DEGREE_BITS - 1 downto 0);

	signal mult_start        : std_logic;
	signal mult_input_A      : unsigned(RNG_WIDTH - 1 downto 0);
	signal mult_input_B      : unsigned(DEGREE_BITS - 1 downto 0);
	signal mult_output       : unsigned(RNG_WIDTH + DEGREE_BITS - 1 downto 0);
	signal mult_output_valid : std_logic;
begin
	fsm_process : process(clock, reset) is
	begin
		if reset = '1' then
			state_rejmod <= IDLE;
			done         <= '0';
			--output_valid <= '0';
			enable_rng   <= '0';

			mult_start   <= '0';
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
					x          <= unsigned(rng_input);
					s          <= to_unsigned(DEGREE - counter, DEGREE_BITS);
					mult_start <= '1';

					state_rejmod <= RUNNING;

					enable_rng <= '0';

				when RUNNING =>
					mult_start <= '0';

					if mult_output_valid = '1' then
						state_rejmod <= START_PIPE;
						enable_rng   <= '1';

						if valid_sample = '1' then
							counter <= counter + 1;

							if counter = DEGREE - 1 then
								state_rejmod <= COMPLETE;

								enable_rng <= '0';
								counter    <= 0;
							end if;
						end if;
					end if;
				when OUTPUT_SAMPLES =>
					counter <= counter + 1;
					if counter = DEGREE - 1 then
						state_rejmod <= COMPLETE;
						counter      <= 0;
					end if;

					--output_valid <= '1';
				when COMPLETE =>
					state_rejmod <= IDLE;
					done         <= '1';
					--output_valid <= '0';
			end case;

		end if;
	end process fsm_process;

	mult_input_A <= x;
	mult_input_B <= s;

	m       <= unsigned(mult_output);
	m_mod_l <= m(RNG_WIDTH - 1 downto 0);

	valid_sample <= '1' when m_mod_l >= t_array(counter) and mult_output_valid = '1' else '0';

--	si_address_b <= std_logic_vector(to_unsigned(counter, DEGREE_BITS));
--	si_data_in_b <= std_logic_vector(shift_right(m, RNG_WIDTH)(DEGREE_BITS - 1 downto 0));
--	si_write_b   <= valid_sample;
--
--	si_address_a <= std_logic_vector(to_unsigned(counter, DEGREE_BITS));
--	output       <= si_data_out_a;

	output <= std_logic_vector(shift_right(m, RNG_WIDTH)(DEGREE_BITS - 1 downto 0)) when rising_edge(clock);
	output_valid <= valid_sample when rising_edge(clock);
	
	iterative_multiplier_inst : entity work.iterative_multiplier
		generic map(
			WIDTH_A => RNG_WIDTH,
			WIDTH_B => DEGREE_BITS
		)
		port map(
			clock        => clock,
			reset        => reset,
			start        => mult_start,
			input_A      => mult_input_A,
			input_B      => mult_input_B,
			output       => mult_output,
			output_valid => mult_output_valid
		);

--	SDP_dist_RAM_inst : entity work.SDP_dist_RAM
--		generic map(
--			ADDRESS_WIDTH => DEGREE_BITS,
--			DATA_WIDTH    => DEGREE_BITS
--		)
--		port map(
--			clock      => clock,
--			address_a  => si_address_a,
--			data_out_a => si_data_out_a,
--			address_b  => si_address_b,
--			write_b    => si_write_b,
--			data_in_b  => si_data_in_b
--		);

end architecture RTL;
