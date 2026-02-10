-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use ieee.math_real.all;
use work.interfaces_msk.all;

entity IsochronousSampling_masked is
	generic(
		DEGREE           : natural := 761;
		DEGREE_BITS      : natural := 10;
		RNG_WIDTH        : natural := 15;
		WEIGHT           : natural := 286;
		RAND_WIDTH_ADDER : natural := get_rand_req(RNG_WIDTH + 1, NUMBER_LEVELS);
		RAND_WIDTH_MUX   : natural := and_pini_nrnd * (DEGREE_BITS + 1)
	);
	port(
		clock        : in  std_logic;
		reset        : in  std_logic;
		start        : in  std_logic;
		rng_input    : in  t_shared(RNG_WIDTH - 1 downto 0)(shares - 1 downto 0); -- Masked RNG input for rejection sampling. 
		rand_in      : in  std_logic_vector(RAND_WIDTH_ADDER + RAND_WIDTH_MUX - 1 downto 0); -- RNG for masked gadgets
		enable_rng   : out std_logic;   -- This is set to '1' when rng_input will be read
		output       : out t_shared(1 downto 0)(shares - 1 downto 0);
		output_valid : out std_logic;
		done         : out std_logic
	);
end entity IsochronousSampling_masked;

architecture RTL of IsochronousSampling_masked is
	signal rej_start        : std_logic;
	signal rej_rng_input    : t_shared(RNG_WIDTH - 1 downto 0)(shares - 1 downto 0);
	signal rej_enable_rng   : std_logic;
	signal rej_output       : t_shared(DEGREE_BITS - 1 downto 0)(shares - 1 downto 0);
	signal rej_output_valid : std_logic;
	signal rej_done         : std_logic;

	--signal rej_output_trans : t_shared_trans(shares - 1 downto 0)(DEGREE_BITS - 1 downto 0);
	--signal rej_output_check : std_logic_vector(DEGREE_BITS - 1 downto 0);

	type state_type is (IDLE, REJ_SAMPLE_SUFFLE, REJ_SAMPLE_CHECK, REJ_SAMPLE_COMPARE, REJ_SAMPLE_SUB_C0, REJ_SAMPLE_SUB_WAIT, DONE_STATE);
	signal state : state_type := IDLE;

	signal c0_msk       : t_shared(DEGREE_BITS downto 0)(shares - 1 downto 0);
	signal c0_msk_trans : t_shared_trans(shares - 1 downto 0)(DEGREE_BITS downto 0);
	--signal c0_msk_trans_check : t_shared_trans(shares - 1 downto 0)(DEGREE_BITS downto 0);
	--signal c0_check           : std_logic_vector(DEGREE_BITS downto 0);

	--signal unmask_comp : std_logic;

	signal add_one_msk : t_shared_trans(shares - 1 downto 0)(RNG_WIDTH downto 0);

	signal added_input_A  : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal added_input_B  : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal added_output_S : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);

	signal counter_wait : integer range 0 to 15;

	signal mux1_a_input : std_logic_vector((DEGREE_BITS + 1) * shares - 1 downto 0);
	signal mux1_b_input : std_logic_vector((DEGREE_BITS + 1) * shares - 1 downto 0);
	signal mux1_s_input : std_logic_vector(shares - 1 downto 0);
	signal mux1_rnd     : std_logic_vector(RAND_WIDTH_MUX - 1 downto 0);
	signal mux1_out_mux : std_logic_vector((DEGREE_BITS + 1) * shares - 1 downto 0);

	signal output_valid_pipe  : std_logic;
	signal output_valid_pipe2 : std_logic;
	signal output_valid_pipe3 : std_logic;

	signal rej_done_reg : std_logic;

	signal rejS_to_adder_A     : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal rejS_to_adder_B     : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal rejS_to_adder_valid : std_logic;
	signal rejS_from_adder_S   : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);

	signal mult_to_adder_A     : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal mult_to_adder_B     : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal mult_to_adder_valid : std_logic;
	signal mult_from_adder_S   : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);

	signal isoS_to_adder_A     : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal isoS_to_adder_B     : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);
	signal isoS_to_adder_valid : std_logic;
	--signal isoS_from_adder_S   : t_shared(RNG_WIDTH downto 0)(shares - 1 downto 0);

begin

	fsm_process : process(clock, reset) is
	begin
		if reset = '1' then
			state        <= IDLE;
			output_valid <= '0';
			done         <= '0';
			rej_start    <= '0';

			output_valid_pipe  <= '0';
			output_valid_pipe2 <= '0';
			output_valid_pipe3 <= '0';

			isoS_to_adder_valid <= '0';

			rej_done_reg <= '0';
		elsif rising_edge(clock) then
			case state is
				when IDLE =>
					if start = '1' then
						state     <= REJ_SAMPLE_SUFFLE;
						rej_start <= '1';
					end if;

					c0_msk <= t_shared_trans_to_t_shared(c0_msk_trans, DEGREE_BITS + 1, shares);

					rej_done_reg <= '0';
				when REJ_SAMPLE_SUFFLE =>
					rej_start <= '0';

					output_valid <= '0';
					if rej_output_valid = '1' then

						isoS_to_adder_A                           <= (others => (others => '0'));
						isoS_to_adder_A(DEGREE_BITS - 1 downto 0) <= rej_output;

						isoS_to_adder_B                       <= (others => c0_msk(DEGREE_BITS));
						isoS_to_adder_B(DEGREE_BITS downto 0) <= c0_msk;

						isoS_to_adder_valid <= '1';

						state <= REJ_SAMPLE_CHECK;

						counter_wait <= 0;
						--						if unsigned(rej_output) < c0 then
						--							output       <= "00";
						--							output_valid <= '1';
						--							c0           <= c0 - 1;
						--						elsif unsigned(rej_output) < c0 + c1 then
						--							output       <= "01";
						--							output_valid <= '1';
						--							c1           <= c1 - 1;
						--						else
						--							output       <= "11";
						--							output_valid <= '1';
						--						end if;
					end if;

					if rej_done = '1' then
						state <= DONE_STATE;
						done  <= '1';
					end if;
				when REJ_SAMPLE_CHECK =>
					isoS_to_adder_valid <= '1';

					isoS_to_adder_A <= t_shared_trans_to_t_shared(add_one_msk, RNG_WIDTH + 1, shares);
					counter_wait    <= counter_wait + 1;
					state           <= REJ_SAMPLE_COMPARE;
				when REJ_SAMPLE_COMPARE =>
					isoS_to_adder_valid <= '0';

					counter_wait <= counter_wait + 1;

					if counter_wait = 10 then

						-- We  mux for rej_output < c0 
						-- if the highest bit of added_output_S is 0, then the output is positive, which means rej_output - c0  >= 0
						-- This means rej_output >= c0 . This is inverse of rej_output < c0.
						-- So added_output_S(RNG_WIDTH) = 1 means rej_output < c0. 
						-- mux outputs mux1_a_input when mux1_s_input set to 1 
						-- for rej_output < c0, we output 0, so 0 must be applied to mux1_a_input

						mux1_b_input    <= (others => '0');
						mux1_b_input(0) <= '1';

						mux1_b_input(shares * 2 - 1 downto shares) <= rng_input(0);

						mux1_a_input <= (others => '0');

						mux1_s_input <= added_output_S(RNG_WIDTH);

						mux1_rnd <= rand_in(RAND_WIDTH_MUX - 1 downto 0);

						output_valid_pipe <= '1';

						state <= REJ_SAMPLE_SUB_C0;
					end if;

				when REJ_SAMPLE_SUB_C0 =>
					output_valid_pipe <= '0';

					-- we can use the same select signal as before.
					-- c0_msk changes for output 0 (when rej_output < c0)
					-- so mux1_b_input is c0_msk, and mux1_a_input is c0_msk-1, which is the output of the adder
					mux1_b_input <= t_shared_flatten(c0_msk, DEGREE_BITS + 1, shares);
					mux1_a_input <= t_shared_flatten(added_output_S(DEGREE_BITS downto 0), DEGREE_BITS + 1, shares);

					mux1_rnd <= rand_in(RAND_WIDTH_MUX - 1 downto 0);

					state        <= REJ_SAMPLE_SUB_WAIT;
					counter_wait <= 0;
				when REJ_SAMPLE_SUB_WAIT =>

					counter_wait <= counter_wait + 1;

					if counter_wait = 2 then
						state  <= REJ_SAMPLE_SUFFLE;
						c0_msk <= t_shared_pack(mux1_out_mux, DEGREE_BITS + 1, shares);

						if rej_done_reg = '1' then
							state <= DONE_STATE;
							done  <= '1';
						end if;

					end if;
				when DONE_STATE =>
					done  <= '0';
					state <= IDLE;
			end case;

			output_valid_pipe2 <= output_valid_pipe;
			output_valid_pipe3 <= output_valid_pipe2;
			output_valid       <= output_valid_pipe3;

			if rej_done = '1' then
				rej_done_reg <= '1';
			end if;

		end if;
	end process fsm_process;

	rej_rng_input <= rng_input;
	enable_rng    <= '1' when rej_enable_rng = '1' else '0';

	-- use negative version, in order to be able to check the sign for the greater than check.
	c0_msk_trans(0)                   <= std_logic_vector(to_signed(-DEGREE + WEIGHT, DEGREE_BITS + 1));
	c0_msk_trans(shares - 1 downto 1) <= (others => (others => '0'));

	add_one_msk(0)                   <= std_logic_vector(to_unsigned(1, RNG_WIDTH + 1));
	add_one_msk(shares - 1 downto 1) <= (others => (others => '0'));

	output <= t_shared_pack(mux1_out_mux(2 * shares downto 0), 2, shares) when output_valid_pipe3 = '1' and rising_edge(clock);

	-- The following assignments are for debugging, they unmasked various internal signals.
	--c0_msk_trans_check <= t_shared_to_t_shared_trans(c0_msk, DEGREE_BITS + 1, shares);
	--c0_check           <= c0_msk_trans_check(0) XOR c0_msk_trans_check(1); -- TODO Remove

	--rej_output_trans <= t_shared_to_t_shared_trans(rej_output, DEGREE_BITS, shares);
	--rej_output_check <= rej_output_trans(0) XOR rej_output_trans(1); -- TODO Remove

	--unmask_comp <= '1' when unsigned(rej_output_check) >= unsigned(-1 * signed(c0_check)) else '0'; -- TODO Remove

	mux2_gadget_inst : entity work.mux2_gadget
		generic map(
			d    => shares,
			word => DEGREE_BITS + 1
		)
		port map(
			clk     => clock,
			a_input => mux1_a_input,
			b_input => mux1_b_input,
			s_input => mux1_s_input,
			rnd     => mux1_rnd,
			out_mux => mux1_out_mux
		);

	RejSamplingMod_masked_inst : entity work.RejSamplingMod_masked
		generic map(
			DEGREE      => DEGREE,
			DEGREE_BITS => DEGREE_BITS,
			RNG_WIDTH   => RNG_WIDTH
		)
		port map(
			clock               => clock,
			reset               => reset,
			start               => rej_start,
			rng_input           => rej_rng_input,
			enable_rng          => rej_enable_rng,
			output              => rej_output,
			output_valid        => rej_output_valid,
			output_enable       => '1', -- Always enable
			done                => rej_done,
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
			level_rand_requirement => RAND_WIDTH_ADDER
		)
		port map(
			clk     => clock,
			A       => added_input_A,
			B       => added_input_B,
			rand_in => rand_in(RAND_WIDTH_ADDER + RAND_WIDTH_MUX - 1 downto RAND_WIDTH_MUX),
			S       => added_output_S
		);

	added_input_A <= rejS_to_adder_A when rejS_to_adder_valid = '1'
	                 else mult_to_adder_A when mult_to_adder_valid = '1'
	                 else isoS_to_adder_A when isoS_to_adder_valid = '1'
	                 else (others => (others => '0'));

	added_input_B <= rejS_to_adder_B when rejS_to_adder_valid = '1'
	                 else mult_to_adder_B when mult_to_adder_valid = '1'
	                 else isoS_to_adder_B when isoS_to_adder_valid = '1'
	                 else (others => (others => '0'));

	assert_check_adder_access : process(clock, reset) is
	begin
		if reset = '1' then

		elsif rising_edge(clock) then
			assert (rejS_to_adder_valid = '0' and mult_to_adder_valid = '0' and isoS_to_adder_valid = '0') or (rejS_to_adder_valid = '1' and mult_to_adder_valid = '0' and isoS_to_adder_valid = '0') or (rejS_to_adder_valid = '0' and mult_to_adder_valid = '1' and isoS_to_adder_valid = '0') or (rejS_to_adder_valid = '0' and mult_to_adder_valid = '0' and isoS_to_adder_valid = '1') report "Collsiion in using masked adder" severity failure;
		end if;
	end process assert_check_adder_access;

	mult_from_adder_S <= added_output_S;
	rejS_from_adder_S <= added_output_S;
end architecture RTL;
