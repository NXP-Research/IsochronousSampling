-- Copyright 2025 NXP
--
-- SPDX-License-Identifier: MIT

library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use work.interfaces_msk.all;

entity iterative_masked_multiplier is
	generic(
		WIDTH_A : natural := 15;
		WIDTH_B : natural := 10
	);
	port(
		clock          : in  std_logic;
		reset          : in  std_logic;
		start          : in  std_logic;
		input_A        : in  t_shared(WIDTH_A - 1 downto 0)(shares - 1 downto 0); -- First input is masked
		input_B        : in  unsigned(WIDTH_B - 1 downto 0); -- second inout is unmasked and public
		to_adder_A     : out t_shared(WIDTH_A downto 0)(shares - 1 downto 0);
		to_adder_B     : out t_shared(WIDTH_A downto 0)(shares - 1 downto 0);
		to_adder_valid : out std_logic;
		from_adder_S   : in  t_shared(WIDTH_A downto 0)(shares - 1 downto 0);
		output         : out t_shared(WIDTH_A + WIDTH_B - 1 downto 0)(shares - 1 downto 0); -- output is masked
		output_valid   : out std_logic
	);
end entity iterative_masked_multiplier;

architecture RTL of iterative_masked_multiplier is

	constant output_width : natural := WIDTH_A + WIDTH_B;

	signal accumulator : t_shared(output_width - 1 downto 0)(shares - 1 downto 0);

	type state_type is (IDLE, ADD_START, ADD_WAIT);
	signal state : state_type := IDLE;

	signal counter_reg : integer range 0 to WIDTH_B;
	signal valid       : std_logic;

	signal adder_input_A  : t_shared(WIDTH_A downto 0)(shares - 1 downto 0);
	signal adder_input_B  : t_shared(WIDTH_A downto 0)(shares - 1 downto 0);
	signal adder_output_S : t_shared(WIDTH_A downto 0)(shares - 1 downto 0);

	signal adder_input_valid : std_logic;

	signal counter_adder : integer range 0 to 10;

	function masked_shift_right(input_signal : t_shared; shift_index : integer; fn_width : in integer; fn_shares : in integer)
	return t_shared is
		variable temp : t_shared(fn_width - 1 downto 0)(fn_shares - 1 downto 0) := (others => (others => '0'));

		variable temp2 : t_shared(WIDTH_A downto 0)(fn_shares - 1 downto 0) := (others => (others => '0'));
	begin

		temp := input_signal;
		for i in 0 to WIDTH_B - 1 loop
			if i = shift_index then
				exit;
			end if;

			temp(fn_width - 2 downto 0) := temp(fn_width - 1 downto 1);
		end loop;

		temp2 := temp(WIDTH_A downto 0);

		return temp2;
	end function masked_shift_right;

begin
	fsm_process : process(clock, reset) is
		variable counter : integer range 0 to WIDTH_B;
	begin
		if reset = '1' then
			state          <= IDLE;
			valid          <= '0';
			to_adder_valid <= '0';
		elsif rising_edge(clock) then
			case state is
				when IDLE =>
					counter := 0;

					accumulator <= (others => (others => '0'));
					valid       <= '0';

					counter_adder <= 0;

					if start = '1' then
						state <= ADD_START;

						for i in 0 to WIDTH_B loop
							if counter = WIDTH_B or input_B(counter) = '1' then
								exit;
							end if;

							if counter /= WIDTH_B and input_B(counter) = '0' then
								counter := counter + 1;
							end if;
						end loop;
					end if;
				when ADD_START =>

					if counter /= WIDTH_B and input_B(counter) = '1' then

						--adder_input_A                       <= accumulator(WIDTH_A + counter downto counter);
						adder_input_A                       <= masked_shift_right(accumulator, counter, output_width, shares);
						adder_input_B(WIDTH_A - 1 downto 0) <= input_A;

						to_adder_valid <= '1';

						--accumulator <= accumulator + shift_left(resize(input_A, output_width), counter);

						counter_reg <= counter;

						counter       := counter + 1;
						state         <= ADD_WAIT;
						counter_adder <= 0;
					end if;

					for i in 0 to WIDTH_B loop
						if counter = WIDTH_B or input_B(counter) = '1' then
							exit;
						end if;

						if counter /= WIDTH_B and input_B(counter) = '0' then
							counter := counter + 1;
						end if;
					end loop;
				when ADD_WAIT =>
					to_adder_valid <= '0';

					counter_adder <= counter_adder + 1;

					if counter_adder = 10 then
						state <= ADD_START;
						for i in 0 to WIDTH_B - 1 loop
							if i = counter_reg then
								accumulator(WIDTH_A + i downto i) <= adder_output_S;
							end if;
						end loop;

						--accumulator(WIDTH_A + counter_reg downto counter_reg) <= adder_output_S;

						if counter = WIDTH_B then
							state <= IDLE;
							valid <= '1';
						end if;
					end if;

			end case;
		end if;

	end process fsm_process;

	output       <= accumulator;
	output_valid <= valid;

	adder_input_B(WIDTH_A) <= (others => '0');

	--	assert_output : process(accumulator, input_A, input_B, valid) is
	--	begin
	--		if valid = '1' then
	--			assert input_A * input_B = accumulator report "Multiplier output is incorrect" severity failure;
	--		end if;
	--	end process assert_output;

	to_adder_A     <= adder_input_A;
	to_adder_B     <= adder_input_B;
	adder_output_S <= from_adder_S;

	assert WIDTH_A + 1 <= 16 report "WIDTH_A must be smaller than 16" severity failure;
end architecture RTL;
