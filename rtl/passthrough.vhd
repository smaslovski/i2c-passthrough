library ieee;
use ieee.std_logic_1164.all;

entity passthrough is

  port (a, b : inout std_logic);

end entity;

architecture async of passthrough is

  signal dir : std_logic := '0';

begin

  dir <= '1' when (b and not a) = '1' else
         '0' when (a and not b) = '1';

  b   <= '0' when     (dir and not a) = '1' else 'Z';
  a   <= '0' when (not dir and not b) = '1' else 'Z';

end architecture;
