library ieee;
use ieee.std_logic_1164.all;

entity i2c_passthrough is

  port (scl_l, sda_l, scl_r, sda_r : inout std_logic);

end entity;

architecture struct of i2c_passthrough is
begin

  pass_scl: entity work.passthrough(async)
    port map (scl_l, scl_r);

  pass_sda: entity work.passthrough(async)
    port map (sda_l, sda_r);

end architecture;
