-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;

entity IsochronousSampling_SNTRUP_HS is
	generic(
		DEGREE      : natural := 761;
		DEGREE_BITS : natural := 10;
		RNG_WIDTH   : natural := 16;
		WEIGHT      : natural := 286
	);
	port(
		clock        : in  std_logic;
		reset        : in  std_logic;
		start        : in  std_logic;
		rng_input    : in  std_logic_vector(RNG_WIDTH - 1 downto 0);
		enable_rng   : out std_logic;
		output       : out std_logic_vector(1 downto 0);
		output_valid : out std_logic;
		done         : out std_logic
	);
end entity IsochronousSampling_SNTRUP_HS;

architecture RTL of IsochronousSampling_SNTRUP_HS is
	signal rej_start        : std_logic;
	signal rej_rng_input    : std_logic_vector(RNG_WIDTH - 1 downto 0);
	signal rej_enable_rng   : std_logic;
	signal rej_output       : std_logic_vector(DEGREE_BITS - 1 downto 0);
	signal rej_output_valid : std_logic;
	signal rej_done         : std_logic;

	type state_type is (IDLE, SAMPLE_C1, SAMPLE_C1_FINAL, REJ_SAMPLE_SUFFLE, DONE_STATE);
	signal state : state_type := IDLE;

	signal c0 : integer range 0 to DEGREE - 1;
	signal c1 : integer range 0 to DEGREE - 1;

	signal counter              : integer range 0 to WEIGHT - 1;
	signal sample_c1_enable_rng : std_logic;

	signal hamming_weight : integer range 0 to RNG_WIDTH;

	signal first_run_done : std_logic;
begin

	fsm_process : process(clock, reset) is
	begin
		if reset = '1' then
			state        <= IDLE;
			output_valid <= '0';
			done         <= '0';
			rej_start    <= '0';
			output       <= "00";
			counter      <= 0;

			sample_c1_enable_rng <= '0';
			first_run_done       <= '0';
		elsif rising_edge(clock) then
			case state is
				when IDLE =>
					if start = '1' then
						state     <= REJ_SAMPLE_SUFFLE;
						rej_start <= '1';
					end if;

					counter <= 0;
				when REJ_SAMPLE_SUFFLE =>
					rej_start <= '0';

					output_valid <= '0';
					if rej_output_valid = '1' then
						if unsigned(rej_output) < c0 then
							output       <= "00";
							output_valid <= '1';
							c0           <= c0 - 1;
						elsif unsigned(rej_output) < c0 + c1 then
							output       <= "01";
							output_valid <= '1';
							c1           <= c1 - 1;
						else
							output       <= "11";
							output_valid <= '1';
						end if;
					end if;

					if rej_done = '1' then
						state <= SAMPLE_C1;
						c0    <= DEGREE - WEIGHT;
						c1    <= 0;
					end if;
				when SAMPLE_C1 =>
					sample_c1_enable_rng <= '1';
					counter              <= counter + 1;

					c1 <= c1 + hamming_weight;
					if counter = WEIGHT / RNG_WIDTH then
						state <= SAMPLE_C1_FINAL;
					end if;
				when SAMPLE_C1_FINAL =>
					state <= DONE_STATE;
					done  <= '1';
					c1    <= c1 + hamming_weight;

					sample_c1_enable_rng <= '0';
				when DONE_STATE =>
					done  <= '0';
					state <= IDLE;
			end case;
		end if;
	end process fsm_process;

	rej_rng_input <= rng_input;
	enable_rng    <= rej_enable_rng or sample_c1_enable_rng;

	rng_hamming_weight : process(rng_input, state) is
		variable temp : integer range 0 to RNG_WIDTH;

	begin
		temp           := 0;
		for i in 0 to RNG_WIDTH - 1 loop
			if rng_input(i) = '1' and (i <= (WEIGHT - (WEIGHT / RNG_WIDTH) * RNG_WIDTH) or state /= SAMPLE_C1_FINAL) then
				temp := temp + 1;
			end if;
		end loop;
		hamming_weight <= temp;
	end process rng_hamming_weight;

	RejSamplingMod_inst : entity work.RejSamplingMod
		generic map(
			DEGREE      => DEGREE,
			DEGREE_BITS => DEGREE_BITS,
			RNG_WIDTH   => RNG_WIDTH
		)
		port map(
			clock        => clock,
			reset        => reset,
			start        => rej_start,
			rng_input    => rej_rng_input,
			enable_rng   => rej_enable_rng,
			output       => rej_output,
			output_valid => rej_output_valid,
			done         => rej_done
		);

end architecture RTL;
