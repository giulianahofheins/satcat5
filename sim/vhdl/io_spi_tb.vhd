--------------------------------------------------------------------------
-- Copyright 2019 The Aerospace Corporation
--
-- This file is part of SatCat5.
--
-- SatCat5 is free software: you can redistribute it and/or modify it under
-- the terms of the GNU Lesser General Public License as published by the
-- Free Software Foundation, either version 3 of the License, or (at your
-- option) any later version.
--
-- SatCat5 is distributed in the hope that it will be useful, but WITHOUT
-- ANY WARRANTY; without even the implied warranty of MERCHANTABILITY or
-- FITNESS FOR A PARTICULAR PURPOSE.  See the GNU Lesser General Public
-- License for more details.
--
-- You should have received a copy of the GNU Lesser General Public License
-- along with SatCat5.  If not, see <https://www.gnu.org/licenses/>.
--------------------------------------------------------------------------
--
-- Testbench for the SPI-master and SPI-slave interface blocks
--
-- This testbench connects an SPI-master and SPI-slave back-to-back,
-- to confirm successful bidirectional communication in each of the
-- four main SPI modes (Mode 0/1/2/3/).
--
-- The test runs indefinitely, with good coverage after 1 millisecond.
--

library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;
use     ieee.math_real.all; -- for UNIFORM
use     work.common_types.all;
use     work.eth_frame_common.all;

entity io_spi_tb_helper is
    generic (
    SPI_BAUD    : integer;
    SPI_MODE    : integer);
    port (
    refclk_a    : std_logic;    -- Refclk for SPI master
    refclk_b    : std_logic;    -- Refclk for SPI slave
    reset_p     : std_logic);
end io_spi_tb_helper;

architecture tb of io_spi_tb_helper is

-- Error if no data received for N clock cycles
constant DATA_CHECK_INTERVAL : integer := 10000;

-- Stop printing certain error messages after the Nth occurence.
-- (Otherwise, recurring errors can overflow the output log size.)
constant MAX_ERROR_MESSAGES : integer := 100;

-- Physical SPI interface
signal spi_csb      : std_logic;
signal spi_sck      : std_logic;
signal spi_mosi     : std_logic;
signal spi_miso     : std_logic;

-- Tx and Rx data streams
signal txa_data     : byte_t := (others => '0');
signal txa_last     : std_logic := '0';
signal txa_valid    : std_logic := '0';
signal txa_ready    : std_logic;

signal txb_data     : byte_t := (others => '0');
signal txb_valid    : std_logic := '0';
signal txb_ready    : std_logic;

signal rxa_ref      : byte_t := (others => '0');
signal rxa_data     : byte_t;
signal rxa_write    : std_logic;

signal rxb_ref      : byte_t := (others => '0');
signal rxb_data     : byte_t;
signal rxb_write    : std_logic;

-- Flow control for each stream.
-- TODO: Do we need a more dynamic test?
signal rate_a2b     : real := 0.02;

begin

-- Generate input and reference streams.
p_input_a : process(refclk_a)
    variable seed1a, seed1b, seed1c : positive := 25789012;
    variable seed2a, seed2b, seed2c : positive := 18735091;
    variable rand : real := 0.0;
    variable first : std_logic := '1';
begin
    if rising_edge(refclk_a) then
        -- Stream A: A2B Data
        if (reset_p = '1') then
            txa_data    <= (others => '0');
            txa_last    <= '0';
            txa_valid   <= '0';
        elsif (txa_valid = '0' or txa_ready = '1') then
            -- PRNG Stream C: Flow control.
            uniform(seed1c, seed2c, rand);
            if (rand < rate_a2b) then
                -- PRNG Stream C: unsynchronized "LAST" flag.
                uniform(seed1c, seed2c, rand);
                txa_last <= bool2bit(rand < 0.125);
                -- PRNG stream A: Main data stream.
                txa_valid <= '1';
                for n in txa_data'range loop
                    uniform(seed1a, seed2a, rand);
                    txa_data(n) <= bool2bit(rand < 0.5);
                end loop;
            else
                txa_last  <= '0';
                txa_valid <= '0';
            end if;
        end if;

        -- PRNG Stream B: B2A Reference
        if (first = '1' or rxa_write = '1') then
            first := '0';
            for n in rxa_ref'range loop
                uniform(seed1b, seed2b, rand);
                rxa_ref(n) <= bool2bit(rand < 0.5);
            end loop;
        end if;
    end if;
end process;

p_input_b : process(refclk_b)
    variable seed1a, seed1b : positive := 25789012;
    variable seed2a, seed2b : positive := 18735091;
    variable rand : real := 0.0;
    variable first : std_logic := '1';
begin
    if rising_edge(refclk_b) then
        -- PRNG Stream A: A2B Reference
        if (first = '1' or rxb_write = '1') then
            first := '0';
            for n in rxb_ref'range loop
                uniform(seed1a, seed2a, rand);
                rxb_ref(n) <= bool2bit(rand < 0.5);
            end loop;
        end if;

        -- PRNG Stream B: B2A Data
        if (reset_p = '1') then
            txb_data    <= (others => '0');
            txb_valid   <= '0';
        elsif (txb_valid = '0' or txb_ready = '1') then
            -- B2A data stream must always be ready.
            -- (If starved, slave block will insert filler characters.)
            txb_valid <= '1';
            for n in txb_data'range loop
                uniform(seed1b, seed2b, rand);
                txb_data(n) <= bool2bit(rand < 0.5);
            end loop;
        end if;
    end if;
end process;

-- UUT: Master
uut_a : entity work.io_spi_master
    generic map(
    CLKREF_HZ   => 100000000,
    SPI_BAUD    => SPI_BAUD,
    SPI_MODE    => SPI_MODE)
    port map(
    cmd_data    => txa_data,
    cmd_last    => txa_last,
    cmd_valid   => txa_valid,
    cmd_ready   => txa_ready,
    rcvd_data   => rxa_data,
    rcvd_write  => rxa_write,
    spi_csb     => spi_csb,
    spi_sck     => spi_sck,
    spi_sdo     => spi_mosi,
    spi_sdi     => spi_miso,
    ref_clk     => refclk_a,
    reset_p     => reset_p);

-- UUT: Slave
uut_b : entity work.io_spi_slave
    generic map(SPI_MODE => SPI_MODE)
    port map(
    spi_csb     => spi_csb,
    spi_sclk    => spi_sck,
    spi_sdi     => spi_mosi,
    spi_sdo     => spi_miso,
    spi_sdt     => open,
    tx_data     => txb_data,
    tx_valid    => txb_valid,
    tx_ready    => txb_ready,
    rx_data     => rxb_data,
    rx_write    => rxb_write,
    refclk      => refclk_b,
    reset_p     => reset_p);

-- Measure the actual SCLK baud rate.
p_baud : process
    variable t1, t2 : time;
    variable baud_hz : integer;
begin
    -- Stopwatch from 3rd to 4th rising edge of SCLK.
    wait until rising_edge(spi_sck);
    wait until rising_edge(spi_sck);
    wait until rising_edge(spi_sck);
    t1 := now;
    wait until rising_edge(spi_sck);
    t2 := now;
    baud_hz := (1.0 sec) / (t2 - t1);
    report "Baud rate = " & integer'image(baud_hz) & " Hz";
    wait;
end process;

-- Confirm that MISO doesn't "glitch" for less than a full bit-period.
p_glitch : process
    constant ONE_BIT    : time := (1.0 sec / SPI_BAUD);
    constant MIN_GLITCH : time := 0.2 ns;
    constant MAX_GLITCH : time := (2 * ONE_BIT) / 3;
    variable prev, diff : time := 0.0 ns;
    variable prev_miso  : std_logic := '0';
    variable msgcount   : integer := 0;
begin
    wait until (spi_miso'event);
    -- Measure elapsed time, then screen for sub-nanosecond glitches.
    diff := now - prev;
    wait for MIN_GLITCH;
    if (spi_miso /= prev_miso) then
        -- Real transition, note new reference state
        prev := now - MIN_GLITCH;
        prev_miso := spi_miso;
        if ((spi_csb = '0') and (diff < MAX_GLITCH) and (msgcount < MAX_ERROR_MESSAGES)) then
            report "MISO glitch detected: " & time'image(diff) severity error;
            msgcount := msgcount + 1;
        end if;
    end if;
end process;

-- Check each output stream.
p_check_a : process(refclk_a)
    variable elapsed    : integer := DATA_CHECK_INTERVAL;
    variable rxcount    : integer := 0;
    variable msgcount   : integer := 0;
begin
    if rising_edge(refclk_a) then
        if (rxa_write = '1') then
            if ((rxa_ref /= rxa_data) and (msgcount < MAX_ERROR_MESSAGES)) then
                report "B2A mismatch" severity error;
                msgcount := msgcount + 1;
            end if;
            rxcount := rxcount + 1;
        end if;

        if (elapsed > 0) then
            elapsed := elapsed - 1;
        else
            assert (rxcount > 0) report "B2A no data" severity error;
            rxcount := 0;
            elapsed := DATA_CHECK_INTERVAL;
        end if;
    end if;
end process;

p_check_b : process(refclk_b)
    variable elapsed    : integer := 10000;
    variable rxcount    : integer := 0;
    variable msgcount   : integer := 0;
begin
    if rising_edge(refclk_b) then
        if (rxb_write = '1') then
            if ((rxb_ref /= rxb_data) and (msgcount < MAX_ERROR_MESSAGES)) then
                report "A2B mismatch" severity error;
                msgcount := msgcount + 1;
            end if;
            rxcount := rxcount + 1;
        end if;

        if (elapsed > 0) then
            elapsed := elapsed - 1;
        else
            assert (rxcount > 0) report "A2B no data" severity error;
            rxcount := 0;
            elapsed := DATA_CHECK_INTERVAL;
        end if;
    end if;
end process;

end tb;


---------------------------------------------------------------------


library ieee;
use     ieee.std_logic_1164.all;
use     ieee.numeric_std.all;

entity io_spi_tb is
    -- Unit testbench, no I/O ports.
end io_spi_tb;

architecture tb of io_spi_tb is

component io_spi_tb_helper is
    generic (
    SPI_BAUD    : integer;
    SPI_MODE    : integer);
    port (
    refclk_a    : std_logic;
    refclk_b    : std_logic;
    reset_p     : std_logic);
end component;

signal clk_76   : std_logic := '0';
signal clk_98   : std_logic := '0';
signal clk_100  : std_logic := '0';
signal reset_p  : std_logic := '1';

begin

-- Clock and reset generation
clk_76  <= not  clk_76 after 6.58 ns;
clk_98  <= not  clk_98 after 5.11 ns;
clk_100 <= not clk_100 after 5.00 ns;
reset_p <= '0' after 1 us;

-- Instantiate functional-test configuration for each mode.
uut0 : io_spi_tb_helper
    generic map(
    SPI_BAUD    => 10000000,
    SPI_MODE    => 0)
    port map(
    refclk_a    => clk_100,
    refclk_b    => clk_98,
    reset_p     => reset_p);

uut1 : io_spi_tb_helper
    generic map(
    SPI_BAUD    => 10000000,
    SPI_MODE    => 1)
    port map(
    refclk_a    => clk_100,
    refclk_b    => clk_98,
    reset_p     => reset_p);

uut2 : io_spi_tb_helper
    generic map(
    SPI_BAUD    => 10000000,
    SPI_MODE    => 2)
    port map(
    refclk_a    => clk_100,
    refclk_b    => clk_98,
    reset_p     => reset_p);

uut3 : io_spi_tb_helper
    generic map(
    SPI_BAUD    => 10000000,
    SPI_MODE    => 3)
    port map(
    refclk_a    => clk_100,
    refclk_b    => clk_98,
    reset_p     => reset_p);

-- One more instance to cover a borderline clock case (just over 3x)
-- (Note: Actual SCLK rate will be an even divisor of refclk_a, N >= 2)
uut4 : io_spi_tb_helper
    generic map(
    SPI_BAUD    => 25000000,
    SPI_MODE    => 3)
    port map(
    refclk_a    => clk_100,
    refclk_b    => clk_76,
    reset_p     => reset_p);

end tb;
