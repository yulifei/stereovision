library ieee;
use ieee.std_logic_1164.all;
use ieee.numeric_std.all;

use std.textio.read;
use std.textio.write;
use std.textio.writeline;
use std.textio.text;
use std.textio.line;
use std.textio.readline;
use work.txt_util.all;

use work.cam_pkg.all;
use work.sim_pkg.all;

entity tb is
end tb;

architecture impl of tb is
  
  signal clk : std_logic;
  signal rst : std_logic;

  signal pipe_in    : pipe_t;
  signal pipe_out   : pipe_t;
  signal pipe       : pipe_set_t;
  signal stall      : std_logic_vector(MAX_PIPE-1 downto 0);
  signal cfg        : cfg_set_t;
  signal p0_rd_fifo : sim_fifo_t;
  signal p0_wr_fifo : sim_fifo_t;

  signal finish : std_logic := '0';

  signal rgb565_2d : rgb565_2d_t;
  signal gray8_2d : gray8_2d_t;  

  signal mono_2d_l : mono_2d_t;
  signal mono_2d_r : mono_2d_t;
  
begin  -- impl

  ena : for i in 0 to (MAX_PIPE-1) generate
    cfg(i).enable   <= '1';
    cfg(i).identify <= '0';
  end generate ena;

  stall(8) <= '0';

  my_pipe_head : entity work.pipe_head
    generic map (
      ID => 0)
    port map (
      clk      => clk,                  -- [in]
      rst      => rst,                  -- [in]
      cfg      => cfg,                  -- [in]
      pipe_out => pipe(0));             -- [out]

  my_sim_feed : entity work.sim_feed
    generic map (
      ID => 1)
    port map (
      pipe_in   => pipe(0),             -- [in]
      pipe_out  => pipe(1),
      stall_in  => stall(1),
      stall_out => stall(0),
      p0_fifo   => p0_rd_fifo);         -- [inout]

  dut : entity work.win_rgb565
    generic map (
      ID     => 4,
      KERNEL => KERNEL,
      WIDTH  => WIDTH,
      HEIGHT => HEIGHT)
    port map (
      pipe_in      => pipe(1),          -- [in]
      pipe_out     => pipe(2),
      stall_in     => stall(2),
      stall_out    => stall(1),
      rgb565_2d_out => rgb565_2d
      );                                -- [inout]

  dut2 : entity work.census
    generic map (
      ID     => 8,
      KERNEL => KERNEL)
    port map (
      pipe_in     => pipe(2),           -- [in]
      pipe_out    => pipe(3),
      stall_in    => stall(3),
      stall_out   => stall(2),
      rgb565_2d_in => rgb565_2d,
      mono_2d_l => mono_2d_l,
      mono_2d_r => mono_2d_r      
      );                                -- [inout]
  
  dut3 : entity work.disparity
    generic map (
      ID     => 9,
      KERNEL => KERNEL,
      MAX_DISPARITY => MAX_DISPARITY)
    port map (
      pipe_in     => pipe(3),           -- [in]
      pipe_out    => pipe(4),
      stall_in    => stall(4),
      stall_out   => stall(3),
      mono_2d_l => mono_2d_l,
      mono_2d_r => mono_2d_r      
      );                                -- [inout]

  dut4 : entity work.win_gray8
    generic map (
      ID     => 10,
      KERNEL => 5,
      WIDTH  => WIDTH,
      HEIGHT => HEIGHT)
    port map (
      pipe_in      => pipe(4),          -- [in]
      pipe_out     => pipe(5),
      stall_in     => stall(5),
      stall_out    => stall(4),
      gray8_2d_out => gray8_2d
      );                                -- [inout]

  dut5 : entity work.kernel_gray8
    generic map (
      ID     => 14,
      KERNEL => 5)
    port map (
      pipe_in      => pipe(5),          -- [in]
      pipe_out     => pipe(6),
      stall_in     => stall(6),
      stall_out    => stall(5),
      gray8_2d_in => gray8_2d
      );                                -- [inout]


  
  colmux : entity work.color_mux
    generic map (
      ID   => 3,
      MODE => 2)      
    port map (
      pipe_in   => pipe(6),             -- [in]
      pipe_out  => pipe(7),
      stall_in  => stall(7),
      stall_out => stall(6));           -- [inout]

  my_sim_sink : entity work.sim_sink
    generic map (
      ID => 2)
    port map (
      pipe_in   => pipe(7),             -- [in]
      pipe_out  => pipe(8),
      stall_in  => stall(8),
      stall_out => stall(7),
      p0_fifo   => p0_wr_fifo);         -- [inout]

-------------------------------------------------------------------------------  
-- Clock and Rst
-------------------------------------------------------------------------------
  process
  begin  -- process
    clk <= '0';
    wait for 5 ns;
    clk <= '1';
    wait for 5 ns;
  end process;

  process
  begin  -- process
    rst <= '1';
    wait for 100 ns;
    rst <= '0';
    wait;
  end process;

  --  print(hstr(rd_data));

  process
    file f             : text open read_mode is stim_file;
    variable l         : line;
    variable s         : string(1 to (24+16+8+1));
    variable c         : integer := 0;
    variable b         : std_logic_vector((24+16+8+1)-1 downto 0);
  begin
    p0_rd_fifo.stall <= '0';
    while not endfile(f) loop
      readline(f, l);
      read(l, s);                                 --ok
      b               := to_std_logic_vector(s);  --ok
      p0_rd_fifo.data <= b;
      wait until p0_rd_fifo.clk = '0' and p0_rd_fifo.en = '1';
      wait until p0_rd_fifo.clk = '1';
    end loop;
    p0_rd_fifo.stall <= '1';
    wait;
  end process;

  process
    file f             : text open write_mode is sim_file;
    variable s         : string(1 to (24+16+8+1));
    variable c         : integer := 0;
    variable b         : std_logic_vector((24+16+8+1)-1 downto 0);
    variable p         : integer := 0;
    variable l         : line;
  begin
    p0_wr_fifo.stall <= '0';

    write(l, str(WIDTH, 10));
    writeline(f, l);
    write(l, str(HEIGHT, 10));
    writeline(f, l);

    if SKIP > 0 then
      for m in SKIP-1 downto 0 loop
        for j in (HEIGHT-1) downto 0 loop
          for i in (WIDTH-1) downto 0 loop
            wait until p0_wr_fifo.clk = '0' and p0_wr_fifo.en = '1';
            b := p0_wr_fifo.data;
--        write(l, str(b));
--        writeline(f, l);
            wait until p0_wr_fifo.clk = '1';
          end loop;
        end loop;  -- j      
      end loop;  -- m      
    end if;

    for j in (HEIGHT-1) downto 0 loop
      for i in (WIDTH-1) downto 0 loop
        wait until p0_wr_fifo.clk = '0' and p0_wr_fifo.en = '1';
        b := p0_wr_fifo.data;
        write(l, str(b));
        writeline(f, l);
        wait until p0_wr_fifo.clk = '1';
      end loop;
    end loop;  -- j
    report "Done" severity note;
    finish <= '1';
    wait;
  end process;
  
end impl;


