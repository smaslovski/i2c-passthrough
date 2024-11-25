-----------------------------------------
-- Testbench for I2C passthrough module.
-- (c) Stanislav Maslovski, Oct 2024.
-----------------------------------------

library ieee;
use ieee.std_logic_1164.all;

entity tb is end entity;

architecture sim of tb is

  constant dT        : time := 5 us;    -- SCL clock half-period
  constant delta_m   : time := 2 us;    -- SDA transition delay wrt SCL negedge, master
  constant delta_s   : time := 3.5 us;  -- SDA transition delay wrt SCL negedge, slave
  constant address   : std_logic_vector(1 to 7) := "1010101";
  constant data_byte : std_logic_vector(1 to 8) := "11001100";

  signal scl_m, sda_m, scl_s, sda_s : std_logic := 'Z';

  function open_drain(x : std_logic) return std_logic is
    variable res : std_logic;
  begin
    case x is
      when '0' | 'L' => res := '0';
      when '1' | 'H' => res := 'Z';
      when others    => res := 'X';
    end case;
    return res;
  end;

  function str(a : std_logic_vector) return string is
    variable res : string(a'range);
  begin
    for i in a'range loop
      res(i) := std_logic'image(a(i))(2);
    end loop;
    return res;
  end;

begin

  -- weak pull-ups for SCL and SDA on both sides

  scl_m <= 'H'; sda_m <= 'H';
  scl_s <= 'H'; sda_s <= 'H';

  -- passthrough module instance

  i2c_pass_inst: entity work.i2c_passthrough(struct)
    port map (scl_m, sda_m, scl_s, sda_s);

  -- master process

  master: process is

    procedure start is
    begin
      sda_m <= '0';
      wait for dT + delta_m;
    end;

    procedure clk_syn is
    begin
      wait until scl_m'stable(0.1*dT) and scl_m = 'H';  -- handle clock stretching
      wait for 0.9*dT;
    end;

    procedure scl_pulse is
    begin
      scl_m <= '0', 'Z' after dT;
      clk_syn;
    end;

    procedure send(abit : in std_logic) is
    begin
      sda_m <= open_drain(abit) after delta_m;
      scl_pulse;
      sda_m <= 'Z' after delta_m;
    end;

    procedure send(bits : in std_logic_vector) is
    begin
      for i in bits'range loop
        send(bits(i));
      end loop;
    end;

    procedure receive(abit : out std_logic) is
    begin
      scl_m <= '0', 'Z' after dT;
      wait until scl_m'stable(0.1*dT) and scl_m = 'H';  -- handle clock stretching
      abit := To_X01(sda_m);
      wait for 0.9*dT;
    end;

    procedure receive(bits : out std_logic_vector) is
    begin
      for i in bits'range loop
        receive(bits(i));
      end loop;
    end;

    procedure stop is
    begin
      sda_m <= '0';
      scl_m <= '0', 'Z' after dT;
      clk_syn;
      sda_m <= 'Z';
    end;

    variable send_data, data : std_logic_vector(1 to 8);
    variable ack             : std_logic;

  begin

    wait for 4*dT;

    -- write bytes begin

      start;

      -- 7-bit address
      send(address);
      report "master: sent addr: " & str(address);

      -- write/read bit
      send('0');  -- write

      -- get address ACK from slave
      receive(ack);

      send_data := data_byte;

      case ack is

        when '0' =>  -- address ACK received
          loop
            send(send_data);
            report "master: sent data: " & str(send_data);
            receive(ack);  -- get data ACK from slave
            assert ack /= 'X' report "master: metavalue in data ACK" severity failure;
            exit when ack = '1';
            send_data := not send_data;
          end loop;

        when '1' =>
          report "master: no ACK from slave" severity failure;

        when others =>
          report "master: metavalue in ACK" severity failure;

      end case;

      stop;

    -- write bytes end

    wait for 4*dT;

    -- read bytes begin

      start;

      -- 7-bit address
      send(address);
      report "master: sent addr: " & str(address);

      -- write/read bit
      send('1');  -- read

      -- get address ACK from slave
      receive(ack);

      case ack is

        when '0' =>  -- address ACK received
          receive(data);
          report "master: got data: " & str(data);
          send('0');  -- send ACK
          assert data = data_byte report "master: received data mismatch: " & str(data) severity failure;

          receive(data);
          report "master: got data: " & str(data);
          send('1');  -- send NACK to terminate transfer
          assert data = not data_byte report "master: received data mismatch: " & str(data) severity failure;

        when '1' =>
          report "master: no ACK from slave" severity failure;

        when others =>
          report "master: metavalue in ACK" severity failure;

      end case;

      stop;

    -- read bytes end

    wait;

  end process;

  -- slave process

  slave: process is

    constant clock_stretch_dT : time := 5 us;

    procedure at_posedge is
    begin
      wait until rising_edge(scl_s);
    end;

    procedure at_negedge is
    begin
      wait until falling_edge(scl_s);
      scl_s <= '0', 'Z' after clock_stretch_dT;  -- clock stretching
    end;

    procedure receive(abit : out std_logic) is
    begin
      at_posedge; abit := To_X01(sda_s); at_negedge;
    end;

    procedure receive(bits : out std_logic_vector) is
    begin
      for i in bits'range loop
        at_posedge; bits(i) := To_X01(sda_s); at_negedge;
      end loop;
    end;

    procedure send(abit : in std_logic) is
    begin
      sda_s <= open_drain(abit) after delta_s; at_negedge;
      sda_s <= 'Z' after delta_s;
    end;

    procedure send(bits : in std_logic_vector) is
    begin
      for i in bits'range loop
        sda_s <= open_drain(bits(i)) after delta_s; at_negedge;
      end loop;
      sda_s <= 'Z' after delta_s;
    end;

    variable addr            : std_logic_vector(1 to 7);
    variable rw, ack         : std_logic;
    variable send_data, data : std_logic_vector(1 to 8);

  begin

    slave_loop: loop

      -- wait for start
      wait until falling_edge(sda_s) and scl_s = 'H';

      at_negedge;

      -- get address
      receive(addr);
      report "slave: got addr: " & str(addr);

      -- get read/write bit
      receive(rw);

      if addr = address then  -- send ACK
        send('0');
      else
        exit slave_loop;
      end if;

      send_data := data_byte;

      case rw is

        when '0' =>  -- master writes
          receive(data);  -- get data
          report "slave: got data: " & str(data);
          send('0');      -- send ACK
          assert data = data_byte report "slave: received data mismatch: " & str(data) severity failure;

          receive(data);  -- get data
          report "slave: got data: " & str(data);
          send('1');      -- send NACK as indication of the end of transfer
          assert data = not data_byte report "slave: received data mismatch: " & str(data) severity failure;

        when '1' =>  -- master reads
          loop
            -- send data
            send(send_data);
            report "slave: sent data: " & str(send_data);
            -- get ACK/NACK response
            receive(ack);
            assert ack /= 'X' report "slave: metavalue in data ACK" severity failure;
            exit when ack = '1';
            send_data := not send_data;
          end loop;

        when others => report "slave: metavalue in R/W" severity failure;

      end case;

      -- wait for stop
      wait until rising_edge(sda_s) and scl_s = 'H';

    end loop;

  end process;

end architecture;
