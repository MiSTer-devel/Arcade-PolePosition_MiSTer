---------------------------------------------------------------------------------
-- Pole Position (adapted from Xevious) by Dar (darfpga@aol.fr)
-- http://darfpga.blogspot.fr
---------------------------------------------------------------------------------
-- Pole Position / Pole Position II: CPU board, Namco 06xx + 51xx..54xx, sound, video.
---------------------------------------------------------------------------------
-- Educational use only. Do not redistribute synthetized file with roms.
---------------------------------------------------------------------------------

library ieee;
use ieee.std_logic_1164.all;
use ieee.std_logic_unsigned.all;
use ieee.numeric_std.all;

entity poleposition is
port(
 clock_18       : in std_logic;
 reset          : in std_logic;

 -- watchdog enable (OSD); 0 = disabled
 wdog_en        : in std_logic;

 sub_illegal    : out std_logic;

 dn_addr        : in  std_logic_vector(16 downto 0);
 dn_data        : in  std_logic_vector(7 downto 0);
 dn_wr          : in  std_logic;

 -- PP2 IC25 protection custom (MRA mod byte bit 0)
 ic25_en        : in  std_logic;
 -- bootleg I/O board, machine topracern / polepos2bi (MRA mod byte bit 1)
 bootleg_io     : in  std_logic;
 -- bootleg speech board, sound Z80 + TMS5220 (MRA mod byte bit 2)
 bootleg_snd    : in  std_logic;

 gfx_addr       : out std_logic_vector(12 downto 0);
 gfx_data       : in  std_logic_vector(7 downto 0);

 view_gfx_addr  : out std_logic_vector(12 downto 0);
 view_gfx_data  : in  std_logic_vector(7 downto 0);

 road_rom_addr  : out std_logic_vector(14 downto 0);
 road_rom_data  : in  std_logic_vector(7 downto 0);
 scalelut_addr  : out std_logic_vector(11 downto 0);
 scalelut_data  : in  std_logic_vector(7 downto 0);
 sprgfx_addr    : out std_logic_vector(16 downto 0);
 sprgfx_data    : in  std_logic_vector(7 downto 0);

 -- 52xx voice ROM (ioctl index 5 +0x4000, 0x8000 bytes)
 sample52_addr  : out std_logic_vector(14 downto 0);
 sample52_data  : in  std_logic_vector(7 downto 0);

 -- engine waveform ROM (ioctl index 5, 0x0000-0x3FFF)
 engine_addr    : out std_logic_vector(13 downto 0);
 engine_data    : in  std_logic_vector(7 downto 0);

 -- palette PROM load (ioctl index 2, 0x000-0xFFF = R/G/B/alpha/view/vpos-mod/road/sprite)
 prom_wr        : in  std_logic;
 prom_addr      : in  std_logic_vector(11 downto 0);
 prom_data      : in  std_logic_vector(7 downto 0);

 -- WSG waveform PROM (ioctl index 2)
 wsg_prom_wr    : in  std_logic;
 wsg_prom_addr  : in  std_logic_vector(7 downto 0);
 wsg_prom_data  : in  std_logic_vector(7 downto 0);

 video_r        : out std_logic_vector(3 downto 0);
 video_g        : out std_logic_vector(3 downto 0);
 video_b        : out std_logic_vector(3 downto 0);
 video_csync    : out std_logic;
 video_blankn   : out std_logic;
 video_hs       : out std_logic;
 video_vs       : out std_logic;
 video_en       : out std_logic;

 blank_h        : out std_logic;
 blank_v        : out std_logic;

 dip_switch_a   : in std_logic_vector (7 downto 0);
 dip_switch_b   : in std_logic_vector (7 downto 0);

 flip           : in std_logic;
 h_offset	: in signed(5 downto 0);
 v_offset	: in signed(3 downto 0);
 diag_swatch    : in std_logic;

 audio          : out std_logic_vector(15 downto 0);

 self_test      : in std_logic;
 service        : in std_logic;
 coin1          : in std_logic;

 start1         : in std_logic;
 -- fire1 = Gear Change
 fire1          : in std_logic;

 coin2          : in std_logic;
 start2         : in std_logic;

 pause          : in std_logic;

 -- steer_in: steering dial; mcu_rom_*: MB88 ROMs (ioctl index 6: 51xx 0x000, 53xx 0x400, 54xx 0x800)
 steer_in       : in  std_logic_vector(7 downto 0);
 mcu_rom_wr     : in  std_logic;
 mcu_rom_addr   : in  std_logic_vector(11 downto 0);
 mcu_rom_data   : in  std_logic_vector(7 downto 0);

 -- ADC accelerator / brake inputs (MAME ACCEL / BRAKE, 0..0x90)
 accel_in       : in  std_logic_vector(7 downto 0);
 brake_in       : in  std_logic_vector(7 downto 0);

 hs_address     : in  std_logic_vector(10 downto 0);
 hs_data_out    : out std_logic_vector(7 downto 0);
 hs_data_in     : in  std_logic_vector(7 downto 0);
 hs_write       : in std_logic
 );
end poleposition;

architecture struct of poleposition is

 signal reset_n     : std_logic;
 signal clock_18n   : std_logic;

 signal slot        : std_logic_vector(2 downto 0);
 signal slot24      : std_logic_vector(4 downto 0);
 signal ena_vidgen  : std_logic;

 signal hcnt        : std_logic_vector(8 downto 0);
 signal vcnt        : std_logic_vector(8 downto 0);
 signal vblank      : std_logic;

 signal bru_r, bru_g, bru_b : std_logic_vector(3 downto 0);

 -- Z80/Z8002 clock enable = clock_18 /16
 signal cen_cnt     : std_logic_vector(3 downto 0);
 signal cen         : std_logic;

 -- alpha scanout (renderer <-> PolePosition_CPU)
 signal bru_scan_addr   : std_logic_vector(10 downto 0);
 signal alpha_scan_dout : std_logic_vector(15 downto 0);
 signal view_scan_addr_w : std_logic_vector(10 downto 0);
 signal view_scan_dout_w : std_logic_vector(15 downto 0);
 signal hscroll_w        : std_logic_vector(15 downto 0);
 signal road_scan_addr_w   : std_logic_vector(9 downto 0);
 signal road_scan_dout_w   : std_logic_vector(15 downto 0);
 signal sprite_scan_addr_w : std_logic_vector(10 downto 0);
 signal sprite_scan_dout_w : std_logic_vector(15 downto 0);
 signal road_vscroll_w     : std_logic_vector(15 downto 0);

 -- CPU ROM-load derives from the index-0 dn_ stream
 signal cpu_rom_wr    : std_logic;
 signal cpu_ioctl_addr: std_logic_vector(24 downto 0);

 -- watchdog: Z80 $A100 kick; its reset pulse goes to the CPU board only
 signal watchdog_wr_w : std_logic;
 signal wdog_reset_w  : std_logic;
 signal cpu_reset_w   : std_logic;

 -- zero tie-offs for unwired CPU inputs
 signal zero8  : std_logic_vector(7 downto 0);
 signal zero10 : std_logic_vector(9 downto 0);
 signal zero11 : std_logic_vector(10 downto 0);

 signal n06_dout_w     : std_logic_vector(7 downto 0);
 signal n06_data_wr_w  : std_logic;
 signal n06_data_rd_w  : std_logic;
 signal n06_ctrl_wr_w  : std_logic;
 signal n06_ctrl_rd_w  : std_logic;
 signal n06_din_w      : std_logic_vector(7 downto 0);
 signal n06_nmi_n_w    : std_logic;

 signal sb0_w          : std_logic;  -- LS259 q6
 signal namco_reset_w  : std_logic;  -- LS259 q1: Namco MCU reset
 signal chacl_w        : std_logic;  -- LS259 q7: alpha layer enable
 signal mcu_reset_n    : std_logic;                     -- = not reset AND namco_reset_w

 signal n06_chipsel    : std_logic_vector(3 downto 0);
 signal n06_rw0        : std_logic;
 signal n06_chip_dout  : std_logic_vector(7 downto 0);
 signal n06_chip_wr    : std_logic_vector(3 downto 0);
 signal chip0_din      : std_logic_vector(7 downto 0);   -- 51xx read() -> 06xx data_r
 signal chip1_din      : std_logic_vector(7 downto 0);   -- 53xx read() -> 06xx data_r
 signal chip23_din     : std_logic_vector(7 downto 0);  -- 52xx/54xx: no read, 0xFF

 -- IN0 (active low): b7 test, b6 service, b5 coin2, b4 coin1, b2 auto start (sb0 loopback), b1 gear
 signal in0_byte       : std_logic_vector(7 downto 0);
 signal bl_in0_byte    : std_logic_vector(7 downto 0);
 signal in0_51xx       : std_logic_vector(7 downto 0);
 signal dswb_51xx      : std_logic_vector(7 downto 0);
 signal chip1_din_06   : std_logic_vector(7 downto 0);
 signal n06_chipsel_g  : std_logic_vector(3 downto 0);
 signal n06_chip_wr_g  : std_logic_vector(3 downto 0);
 signal bl_dac_w       : std_logic_vector(3 downto 0);
 signal bl_latch_w     : std_logic_vector(7 downto 0);
 signal bl_latch_wr_w  : std_logic;
 signal bl_dac_s       : signed(17 downto 0);
 signal bl_off_n       : std_logic;
 signal n52_sample_addr : std_logic_vector(14 downto 0);
 signal bs_rom_addr     : std_logic_vector(14 downto 0);
 signal bs_audio_w      : std_logic_vector(15 downto 0);
 signal bs_gain_s       : signed(24 downto 0);
 signal bs_audio_s      : signed(17 downto 0);
 signal bs_reset        : std_logic;
 signal bs_latch_wr     : std_logic;

 -- Namco MCU clock enable: cen/12 = 256 kHz, the MB88 machine-cycle rate (1.536 MHz pin clock / 6)
 signal mcu_div : std_logic := '0';
 constant MCU_CEN_DIV : integer := 12;
 signal mcu_div_cnt : integer range 0 to 15 := 0;
 signal mcu_ena : std_logic;

 signal sound_en_w  : std_logic;

 signal engine_dout_w   : std_logic_vector(7 downto 0);
 signal engine_lsb_wr_w : std_logic;
 signal engine_msb_wr_w : std_logic;
 signal wsg_audio_w     : std_logic_vector(15 downto 0);
 signal engine_audio_w  : std_logic_vector(15 downto 0);
 signal n52_p_w         : std_logic_vector(3 downto 0);
 signal voice_audio_w   : std_logic_vector(15 downto 0);
 signal n54_o0_w        : std_logic_vector(3 downto 0);
 signal n54_o1_w        : std_logic_vector(3 downto 0);
 signal n54_r1_w        : std_logic_vector(3 downto 0);
 signal noise_audio_w   : std_logic_vector(15 downto 0);
 signal audio_mix_s     : signed(17 downto 0);
 signal wsg_gain_s      : signed(24 downto 0);  -- x0.80
 signal voice_gain_s    : signed(24 downto 0);  -- x0.90
 signal wsg_addr_w  : std_logic_vector(5 downto 0);
 signal wsg_dout_w  : std_logic_vector(7 downto 0);
 signal wsg_wr_w    : std_logic;
 signal wsg_din_w   : std_logic_vector(7 downto 0);

 signal gasel_w      : std_logic;  -- LS259 q3: 0 = brake, 1 = accel
 signal adc_wr_w     : std_logic;
 signal adc_rd_w     : std_logic;
 signal adc_din_w    : std_logic_vector(7 downto 0);
 signal adc_intr_n_w : std_logic;
 signal adc_vin_w    : std_logic_vector(7 downto 0);

 component pp_bootleg_snd
 port(
   clk           : in  std_logic;
   cen           : in  std_logic;
   reset         : in  std_logic;
   pause         : in  std_logic;
   latch_wr      : in  std_logic;
   latch_din     : in  std_logic_vector(7 downto 0);
   rom_addr      : out std_logic_vector(14 downto 0);
   rom_data      : in  std_logic_vector(7 downto 0);
   audio         : out std_logic_vector(15 downto 0);
   tms_wr_data   : out std_logic_vector(7 downto 0);
   tms_wr_strobe : out std_logic
 );
 end component;

 component namco_06xx
 port(
   clk        : in  std_logic;
   reset      : in  std_logic;
   pause      : in  std_logic;
   cpu_dout   : in  std_logic_vector(7 downto 0);
   data_wr    : in  std_logic;
   data_rd    : in  std_logic;
   ctrl_wr    : in  std_logic;
   ctrl_rd    : in  std_logic;
   cpu_din    : out std_logic_vector(7 downto 0);
   nmi_n      : out std_logic;
   chipsel    : out std_logic_vector(3 downto 0);
   rw0        : out std_logic;
   chip0_din  : in  std_logic_vector(7 downto 0);
   chip1_din  : in  std_logic_vector(7 downto 0);
   chip2_din  : in  std_logic_vector(7 downto 0);
   chip3_din  : in  std_logic_vector(7 downto 0);
   chip_dout  : out std_logic_vector(7 downto 0);
   chip_wr    : out std_logic_vector(3 downto 0)
 );
 end component;

 component namco_51xx
 port(
   clk          : in  std_logic;
   ena          : in  std_logic;
   reset_n      : in  std_logic;
   chip_sel     : in  std_logic;
   rw_in        : in  std_logic;
   data_out     : out std_logic_vector(7 downto 0);
   wr_en        : in  std_logic;
   wr_data      : in  std_logic_vector(7 downto 0);
   dswb         : in  std_logic_vector(7 downto 0);
   in0          : in  std_logic_vector(7 downto 0);
   p_port_out   : out std_logic_vector(3 downto 0);
   rom_wr       : in  std_logic;
   rom_addr_in  : in  std_logic_vector(11 downto 0);
   rom_data_in  : in  std_logic_vector(7 downto 0);
   vblank       : in  std_logic
 );
 end component;

 component namco_53xx
 port(
   clk          : in  std_logic;
   ena          : in  std_logic;
   reset_n      : in  std_logic;
   chip_sel     : in  std_logic;
   data_out     : out std_logic_vector(7 downto 0);
   dswa         : in  std_logic_vector(7 downto 0);
   steer_in     : in  std_logic_vector(7 downto 0);
   rom_wr       : in  std_logic;
   rom_addr_in  : in  std_logic_vector(11 downto 0);
   rom_data_in  : in  std_logic_vector(7 downto 0)
 );
 end component;

 component namco_54xx
 port(
   clk          : in  std_logic;
   ena          : in  std_logic;
   reset_n      : in  std_logic;
   chip_sel     : in  std_logic;
   wr_en        : in  std_logic;
   wr_data      : in  std_logic_vector(7 downto 0);
   discrete_o0  : out std_logic_vector(3 downto 0);
   discrete_o1  : out std_logic_vector(3 downto 0);
   discrete_r1  : out std_logic_vector(3 downto 0);
   rom_wr       : in  std_logic;
   rom_addr_in  : in  std_logic_vector(11 downto 0);
   rom_data_in  : in  std_logic_vector(7 downto 0)
 );
 end component;

 component namco_52xx
 port(
   clk          : in  std_logic;
   ena          : in  std_logic;
   reset_n      : in  std_logic;
   chip_sel     : in  std_logic;
   wr_en        : in  std_logic;
   wr_data      : in  std_logic_vector(7 downto 0);
   discrete_p   : out std_logic_vector(3 downto 0);
   sample_addr  : out std_logic_vector(14 downto 0);
   sample_data  : in  std_logic_vector(7 downto 0);
   rom_wr       : in  std_logic;
   rom_addr_in  : in  std_logic_vector(11 downto 0);
   rom_data_in  : in  std_logic_vector(7 downto 0)
 );
 end component;

 -- engine sound
 component pp_engine_snd
 port(
   clk       : in  std_logic;
   reset     : in  std_logic;
   pause     : in  std_logic;
   clson     : in  std_logic;
   lsb_wr    : in  std_logic;
   msb_wr    : in  std_logic;
   din       : in  std_logic_vector(7 downto 0);
   rom_addr  : out std_logic_vector(13 downto 0);
   rom_data  : in  std_logic_vector(7 downto 0);
   audio     : out std_logic_vector(15 downto 0)
 );
 end component;

 -- 52xx voice analog stage
 component pp_voice52_snd
 port(
   clk       : in  std_logic;
   reset     : in  std_logic;
   pause     : in  std_logic;
   p_data    : in  std_logic_vector(3 downto 0);
   audio     : out std_logic_vector(15 downto 0)
 );
 end component;

 -- 54xx noise analog stage
 component pp_noise54_snd
 port(
   clk       : in  std_logic;
   reset     : in  std_logic;
   pause     : in  std_logic;
   o0_data   : in  std_logic_vector(3 downto 0);
   o1_data   : in  std_logic_vector(3 downto 0);
   r1_data   : in  std_logic_vector(3 downto 0);
   audio     : out std_logic_vector(15 downto 0)
 );
 end component;

 component namco_wsg8
 port(
   clk       : in  std_logic;
   reset     : in  std_logic;
   sound_en  : in  std_logic;
   pause     : in  std_logic;
   reg_addr  : in  std_logic_vector(5 downto 0);
   reg_din   : in  std_logic_vector(7 downto 0);
   reg_wr    : in  std_logic;
   reg_dout  : out std_logic_vector(7 downto 0);
   wave_wr   : in  std_logic;
   wave_addr : in  std_logic_vector(7 downto 0);
   wave_data : in  std_logic_vector(7 downto 0);
   audio     : out std_logic_vector(15 downto 0)
 );
 end component;

 component adc0804
 port(
   clk      : in  std_logic;
   reset    : in  std_logic;
   wr       : in  std_logic;
   rd       : in  std_logic;
   vin      : in  std_logic_vector(7 downto 0);
   dout     : out std_logic_vector(7 downto 0);
   intr_n   : out std_logic
 );
 end component;

 component pp_video_composite
 port(
   clk             : in  std_logic;
   ce              : in  std_logic;
   hpos            : in  std_logic_vector(8 downto 0);
   vpos            : in  std_logic_vector(8 downto 0);
   chacl           : in  std_logic;
   diag_swatch     : in  std_logic;  -- palette swatch overlay
   alpha_scan_addr : out std_logic_vector(10 downto 0);
   alpha_scan_dout : in  std_logic_vector(15 downto 0);
   alpha_gfx_addr  : out std_logic_vector(12 downto 0);
   alpha_gfx_data  : in  std_logic_vector(7 downto 0);
   view_scan_addr  : out std_logic_vector(10 downto 0);
   view_scan_dout  : in  std_logic_vector(15 downto 0);
   view_gfx_addr   : out std_logic_vector(12 downto 0);
   view_gfx_data   : in  std_logic_vector(7 downto 0);
   view_hscroll    : in  std_logic_vector(15 downto 0);
   road_scan_addr  : out std_logic_vector(9 downto 0);
   road_scan_dout  : in  std_logic_vector(15 downto 0);
   road_rom_addr   : out std_logic_vector(14 downto 0);
   road_rom_data   : in  std_logic_vector(7 downto 0);
   road_vscroll    : in  std_logic_vector(15 downto 0);
   sprite_scan_addr: out std_logic_vector(10 downto 0);
   sprite_scan_dout: in  std_logic_vector(15 downto 0);
   scalelut_addr   : out std_logic_vector(11 downto 0);
   scalelut_data   : in  std_logic_vector(7 downto 0);
   sprgfx_addr     : out std_logic_vector(16 downto 0);
   sprgfx_data     : in  std_logic_vector(7 downto 0);
   prom_wr         : in  std_logic;
   prom_addr       : in  std_logic_vector(11 downto 0);
   prom_data       : in  std_logic_vector(7 downto 0);
   r               : out std_logic_vector(3 downto 0);
   g               : out std_logic_vector(3 downto 0);
   b               : out std_logic_vector(3 downto 0)
 );
 end component;

 component PolePosition_CPU
 port(
   clk              : in  std_logic;
   cen              : in  std_logic;
   reset            : in  std_logic;
   pause            : in  std_logic;
   vpos             : in  std_logic_vector(8 downto 0);
   sub1_reset_n     : out std_logic;
   sub2_reset_n     : out std_logic;
   namco_reset      : out std_logic;
   sound_en         : out std_logic;
   gasel            : out std_logic;
   sb0              : out std_logic;
   chacl            : out std_logic;
   sub_nvi_trig     : out std_logic;
   vram_addr        : out std_logic_vector(12 downto 0);
   vram_dout        : out std_logic_vector(7 downto 0);
   vram_wr          : out std_logic;
   vram_rd          : out std_logic;
   vram_din         : in  std_logic_vector(7 downto 0);
   n06_dout         : out std_logic_vector(7 downto 0);
   n06_data_wr      : out std_logic;
   n06_data_rd      : out std_logic;
   n06_ctrl_wr      : out std_logic;
   n06_ctrl_rd      : out std_logic;
   n06_din          : in  std_logic_vector(7 downto 0);
   n06_nmi_n        : in  std_logic;
   wsg_addr         : out std_logic_vector(5 downto 0);
   wsg_dout         : out std_logic_vector(7 downto 0);
   wsg_wr           : out std_logic;
   wsg_rd           : out std_logic;
   wsg_din          : in  std_logic_vector(7 downto 0);
   engine_dout      : out std_logic_vector(7 downto 0);
   engine_lsb_wr    : out std_logic;
   engine_msb_wr    : out std_logic;
   adc_wr           : out std_logic;
   adc_rd           : out std_logic;
   adc_din          : in  std_logic_vector(7 downto 0);
   adc_intr_n       : in  std_logic;
   watchdog_wr      : out std_logic;
   sub_illegal      : out std_logic;
   ioctl_addr       : in  std_logic_vector(24 downto 0);
   ioctl_data       : in  std_logic_vector(7 downto 0);
   rom_wr           : in  std_logic;
   ioctl_wr_idx0    : in  std_logic;
   ic25_en          : in  std_logic;
   bootleg_io       : in  std_logic;
   bl_steer         : in  std_logic_vector(7 downto 0);
   bl_in0           : in  std_logic_vector(7 downto 0);
   bl_dswa          : in  std_logic_vector(7 downto 0);
   bl_dswb          : in  std_logic_vector(7 downto 0);
   bl_dac           : out std_logic_vector(3 downto 0);
   bl_latch         : out std_logic_vector(7 downto 0);
   bl_latch_wr      : out std_logic;
   scan_sprite_addr : in  std_logic_vector(10 downto 0);
   scan_sprite_dout : out std_logic_vector(15 downto 0);
   scan_road_addr   : in  std_logic_vector(9 downto 0);
   scan_road_dout   : out std_logic_vector(15 downto 0);
   scan_alpha_addr  : in  std_logic_vector(9 downto 0);
   scan_alpha_dout  : out std_logic_vector(15 downto 0);
   scan_view_addr   : in  std_logic_vector(10 downto 0);
   scan_view_dout   : out std_logic_vector(15 downto 0);
   hscroll          : out std_logic_vector(15 downto 0);
   vscroll          : out std_logic_vector(15 downto 0);
   hs_address       : in  std_logic_vector(10 downto 0);
   hs_data_out      : out std_logic_vector(7 downto 0);
   hs_data_in       : in  std_logic_vector(7 downto 0);
   hs_write         : in  std_logic
 );
 end component;

 component pp_watchdog
 port(
   clk        : in  std_logic;
   reset      : in  std_logic;
   wdog_en    : in  std_logic;
   vpos       : in  std_logic_vector(8 downto 0);
   kick       : in  std_logic;
   pause      : in  std_logic;
   wdog_reset : out std_logic
 );
 end component;

 component gen_video
 port(
   clk      : in  std_logic;
   enable   : in  std_logic;
   hcnt     : out std_logic_vector(8 downto 0);
   vcnt     : out std_logic_vector(8 downto 0);
   hsync    : out std_logic;
   vsync    : out std_logic;
   csync    : out std_logic;
   blank_h  : out std_logic;
   blank_v  : out std_logic;
   blankn   : out std_logic;
   h_offset : in  signed(5 downto 0);
   v_offset : in  signed(3 downto 0)
 );
 end component;

begin

reset_n    <= not reset;
clock_18n  <= not clock_18;

-- CPU board reset = system reset OR watchdog
cpu_reset_w <= reset or wdog_reset_w;

zero8  <= (others => '0');
zero10 <= (others => '0');
zero11 <= (others => '0');

blank_v      <= vblank;
video_en     <= ena_vidgen;

cpu_ioctl_addr <= "00000000" & dn_addr;
cpu_rom_wr     <= dn_wr when dn_addr(16 downto 12) < "00011" else '0';  -- maincpu region < 0x3000

process (clock_18)
begin
	if rising_edge(clock_18) then
		if reset = '1' then
			cen_cnt <= (others => '0');
		else
			cen_cnt <= cen_cnt + "0001";
		end if;
	end if;
end process;
cen <= '1' when cen_cnt = "0000" else '0';

-- pixel clock enable: 1-in-8 of 49.152 MHz = 6.144 MHz (MAME MASTER_CLOCK/4)
process (clock_18)
begin
	if rising_edge(clock_18) then
		slot24     <= slot24 + "00001";
		slot       <= slot + "001";
		ena_vidgen <= '0';
		if slot = "111" then ena_vidgen <= '1'; end if;
	end if;
end process;

-- H/V sync + counters (reused as-is; 384x264 Namco-family timing)
u_gen_video : gen_video
port map(
	clk      => clock_18,
	enable   => ena_vidgen,
	hcnt     => hcnt,
	vcnt     => vcnt,
	hsync    => video_hs,
	vsync    => video_vs,
	csync    => video_csync,
	blank_h  => blank_h,
	blank_v  => vblank,
	blankn   => video_blankn,
	h_offset => h_offset,
	v_offset => v_offset
);

-- video compositor: view / road, sprites, alpha (MAME screen_update)
u_video_composite : pp_video_composite
port map(
	clk              => clock_18,
	ce               => ena_vidgen,
	hpos             => hcnt,
	vpos             => vcnt,
	chacl            => chacl_w,
	diag_swatch      => diag_swatch,
	alpha_scan_addr  => bru_scan_addr,
	alpha_scan_dout  => alpha_scan_dout,
	alpha_gfx_addr   => gfx_addr,
	alpha_gfx_data   => gfx_data,
	view_scan_addr   => view_scan_addr_w,
	view_scan_dout   => view_scan_dout_w,
	view_gfx_addr    => view_gfx_addr,
	view_gfx_data    => view_gfx_data,
	view_hscroll     => hscroll_w,
	road_scan_addr   => road_scan_addr_w,
	road_scan_dout   => road_scan_dout_w,
	road_rom_addr    => road_rom_addr,
	road_rom_data    => road_rom_data,
	road_vscroll     => road_vscroll_w,
	sprite_scan_addr => sprite_scan_addr_w,
	sprite_scan_dout => sprite_scan_dout_w,
	scalelut_addr    => scalelut_addr,
	scalelut_data    => scalelut_data,
	sprgfx_addr      => sprgfx_addr,
	sprgfx_data      => sprgfx_data,
	prom_wr          => prom_wr,
	prom_addr        => prom_addr,
	prom_data        => prom_data,
	r                => bru_r,
	g                => bru_g,
	b                => bru_b
);

-- CPU board: Z80 + 2x Z8002 + shared video RAM
u_pp_cpu : PolePosition_CPU
port map(
	clk              => clock_18,
	cen              => cen,
	reset            => cpu_reset_w,
	pause            => pause,
	vpos             => vcnt,
	sub1_reset_n     => open,
	sub2_reset_n     => open,
	namco_reset      => namco_reset_w,
	sound_en         => sound_en_w,
	gasel            => gasel_w,
	sb0              => sb0_w,
	chacl            => chacl_w,
	sub_nvi_trig     => open,
	vram_addr        => open,
	vram_dout        => open,
	vram_wr          => open,
	vram_rd          => open,
	vram_din         => zero8,
	n06_dout         => n06_dout_w,
	n06_data_wr      => n06_data_wr_w,
	n06_data_rd      => n06_data_rd_w,
	n06_ctrl_wr      => n06_ctrl_wr_w,
	n06_ctrl_rd      => n06_ctrl_rd_w,
	n06_din          => n06_din_w,
	n06_nmi_n        => n06_nmi_n_w,
	wsg_addr         => wsg_addr_w,
	wsg_dout         => wsg_dout_w,
	wsg_wr           => wsg_wr_w,
	wsg_rd           => open,
	wsg_din          => wsg_din_w,
	engine_dout      => engine_dout_w,
	engine_lsb_wr    => engine_lsb_wr_w,
	engine_msb_wr    => engine_msb_wr_w,
	adc_wr           => adc_wr_w,
	adc_rd           => adc_rd_w,
	adc_din          => adc_din_w,
	adc_intr_n       => adc_intr_n_w,
	watchdog_wr      => watchdog_wr_w,
	sub_illegal      => sub_illegal,
	ioctl_addr       => cpu_ioctl_addr,
	ioctl_data       => dn_data,
	rom_wr           => cpu_rom_wr,
	ioctl_wr_idx0    => dn_wr,
	ic25_en          => ic25_en,
	bootleg_io       => bootleg_io,
	bl_steer         => steer_in,
	bl_in0           => bl_in0_byte,
	bl_dswa          => dip_switch_a,
	bl_dswb          => dip_switch_b,
	bl_dac           => bl_dac_w,
	bl_latch         => bl_latch_w,
	bl_latch_wr      => bl_latch_wr_w,
	scan_sprite_addr => sprite_scan_addr_w,
	scan_sprite_dout => sprite_scan_dout_w,
	scan_road_addr   => road_scan_addr_w,
	scan_road_dout   => road_scan_dout_w,
	scan_alpha_addr  => bru_scan_addr(9 downto 0),
	scan_alpha_dout  => alpha_scan_dout,
	scan_view_addr   => view_scan_addr_w,
	scan_view_dout   => view_scan_dout_w,
	hscroll          => hscroll_w,
	vscroll          => road_vscroll_w,
	hs_address       => hs_address,
	hs_data_out      => hs_data_out,
	hs_data_in       => hs_data_in,
	hs_write         => hs_write
);

u_watchdog : pp_watchdog
port map(
	clk        => clock_18,
	reset      => reset,
	wdog_en    => wdog_en,
	vpos       => vcnt,
	kick       => watchdog_wr_w,
	pause      => pause,
	wdog_reset => wdog_reset_w
);

adc_vin_w <= accel_in when gasel_w = '1' else brake_in;

u_adc : adc0804
port map(
	clk      => clock_18,
	reset    => reset,
	wr       => adc_wr_w,
	rd       => adc_rd_w,
	vin      => adc_vin_w,
	dout     => adc_din_w,
	intr_n   => adc_intr_n_w
);

u_wsg : namco_wsg8
port map(
	clk       => clock_18,
	reset     => reset,
	sound_en  => sound_en_w,
	pause     => pause,
	reg_addr  => wsg_addr_w,
	reg_din   => wsg_dout_w,
	reg_wr    => wsg_wr_w,
	reg_dout  => wsg_din_w,
	wave_wr   => wsg_prom_wr,
	wave_addr => wsg_prom_addr,
	wave_data => wsg_prom_data,
	audio     => wsg_audio_w
);

-- engine sound (MAME polepos_a.cpp polepos_sound_device)
u_engine : pp_engine_snd
port map(
	clk      => clock_18,
	reset    => reset,
	pause    => pause,
	clson    => sound_en_w,
	lsb_wr   => engine_lsb_wr_w,
	msb_wr   => engine_msb_wr_w,
	din      => engine_dout_w,
	rom_addr => engine_addr,
	rom_data => engine_data,
	audio    => engine_audio_w
);

-- 52xx voice: DAC + filters on the 52xx's 4-bit output
u_voice52 : pp_voice52_snd
port map(
	clk    => clock_18,
	reset  => reset,
	pause  => pause,
	p_data => n52_p_w,
	audio  => voice_audio_w
);

-- 54xx noise: DAC + bandpass on the 54xx's three 4-bit outputs
u_noise54 : pp_noise54_snd
port map(
	clk     => clock_18,
	reset   => reset,
	pause   => pause,
	o0_data => n54_o0_w,
	o1_data => n54_o1_w,
	r1_data => n54_r1_w,
	audio   => noise_audio_w
);

-- bootleg speech board; its Z80 program sits in the (absent) 52xx's voice-ROM slot
u_bootleg_snd : pp_bootleg_snd
port map(
	clk           => clock_18,
	cen           => cen,
	reset         => bs_reset,
	pause         => pause,
	latch_wr      => bs_latch_wr,
	latch_din     => bl_latch_w,
	rom_addr      => bs_rom_addr,
	rom_data      => sample52_data,
	audio         => bs_audio_w,
	tms_wr_data   => open,
	tms_wr_strobe => open
);
bs_reset      <= cpu_reset_w or not bootleg_snd;  -- VHDL-93: no expressions in port maps
bs_latch_wr   <= bl_latch_wr_w and bootleg_snd;
sample52_addr <= bs_rom_addr when bootleg_snd = '1' else n52_sample_addr;
-- speech: MAME TMS5220 route 0.80, front speakers only -> 0.40 in this mono mix
bs_gain_s  <= signed(bs_audio_w) * to_signed(102, 9);
bs_audio_s <= resize(shift_right(bs_gain_s, 8), 18) when bootleg_snd = '1' else (others => '0');

-- mix gains: WSG 0.80 x2 (music level), 52xx 0.90 (MAME routes); engine and 54xx are scaled in their modules
wsg_gain_s   <= signed(wsg_audio_w)   * to_signed(205, 9);
voice_gain_s <= signed(voice_audio_w) * to_signed(230, 9);
-- bootleg 4-bit DAC: (v - 8) at 0.12 of full scale (MAME route)
bl_dac_s <= resize((signed(resize(unsigned(bl_dac_w), 5)) - 8) * to_signed(492, 11), 18) when bootleg_io = '1' else (others => '0');
audio_mix_s <= resize(shift_right(wsg_gain_s, 7), 18) + resize(signed(engine_audio_w), 18)
                                                      + resize(shift_right(voice_gain_s, 8), 18)
                                                      + resize(signed(noise_audio_w), 18)
                                                      + bl_dac_s
                                                      + bs_audio_s;
audio <= x"7FFF" when audio_mix_s >  to_signed(32767, 18) else
         x"8000" when audio_mix_s < to_signed(-32768, 18) else
         std_logic_vector(audio_mix_s(15 downto 0));

process (clock_18)
begin
	if rising_edge(clock_18) then
		if reset = '1' then
			mcu_div <= '0';
			mcu_div_cnt <= 0;
		elsif cen = '1' then
			mcu_div <= not mcu_div;
			if mcu_div_cnt = MCU_CEN_DIV - 1 then
				mcu_div_cnt <= 0;
			else
				mcu_div_cnt <= mcu_div_cnt + 1;
			end if;
		end if;
	end if;
end process;
mcu_ena <= '1' when (cen = '1' and mcu_div_cnt = MCU_CEN_DIV - 1 and pause = '0') else '0';

-- Namco MCUs: reset by system reset or LS259 q1
mcu_reset_n <= (not reset) and namco_reset_w;

-- IN0 bit 2 follows sb0 directly: program-controlled auto start (IP_ACTIVE_LOW cancels MAME's !sb0)
in0_byte <= (not self_test) & (not service) & (not coin2) & (not coin1)
            & '1' & sb0_w & (not fire1) & '1';

-- bootleg I/O board IN0 (active low): b7 test, b6 coin1, b5 gear; the 51xx sees only IN0>>4 (MAME)
bl_in0_byte <= (not self_test) & (not coin1) & (not fire1) & '1' & '0' & "111";
in0_51xx    <= (bl_in0_byte(7 downto 4) & "0000") when bootleg_io = '1' else in0_byte;
dswb_51xx   <= x"00" when bootleg_io = '1' else dip_switch_b;
-- bootleg board has no 53xx/52xx/54xx: chips 1-3 deselected, chip 1 reads FF
bl_off_n      <= not bootleg_io;
n06_chipsel_g <= (n06_chipsel(3) and bl_off_n) & (n06_chipsel(2) and bl_off_n)
               & (n06_chipsel(1) and bl_off_n) & n06_chipsel(0);
n06_chip_wr_g <= (n06_chip_wr(3) and bl_off_n) & (n06_chip_wr(2) and bl_off_n)
               & (n06_chip_wr(1) and bl_off_n) & n06_chip_wr(0);
chip1_din_06  <= x"FF" when bootleg_io = '1' else chip1_din;

-- 52xx/54xx have no read callback (MAME): 0xFF
chip23_din <= (others => '1');

u_n06xx : namco_06xx
port map(
	clk       => clock_18,
	reset     => reset,
	pause     => pause,
	cpu_dout  => n06_dout_w,
	data_wr   => n06_data_wr_w,
	data_rd   => n06_data_rd_w,
	ctrl_wr   => n06_ctrl_wr_w,
	ctrl_rd   => n06_ctrl_rd_w,
	cpu_din   => n06_din_w,
	nmi_n     => n06_nmi_n_w,
	chipsel   => n06_chipsel,
	rw0       => n06_rw0,
	chip0_din => chip0_din,
	chip1_din => chip1_din_06,
	chip2_din => chip23_din,
	chip3_din => chip23_din,
	chip_dout => n06_chip_dout,
	chip_wr   => n06_chip_wr
);

u_n51xx : namco_51xx
port map(
	clk         => clock_18,
	ena         => mcu_ena,
	reset_n     => mcu_reset_n,
	chip_sel    => n06_chipsel(0),
	rw_in       => n06_rw0,
	data_out    => chip0_din,
	wr_en       => n06_chip_wr(0),
	wr_data     => n06_chip_dout,
	dswb        => dswb_51xx,
	in0         => in0_51xx,
	p_port_out  => open,
	rom_wr      => mcu_rom_wr,
	rom_addr_in => mcu_rom_addr,
	rom_data_in => mcu_rom_data,
	vblank      => vblank
);

u_n53xx : namco_53xx
port map(
	clk         => clock_18,
	ena         => mcu_ena,
	reset_n     => mcu_reset_n,
	chip_sel    => n06_chipsel_g(1),
	data_out    => chip1_din,
	dswa        => dip_switch_a,
	steer_in    => steer_in,
	rom_wr      => mcu_rom_wr,
	rom_addr_in => mcu_rom_addr,
	rom_data_in => mcu_rom_data
);

-- 54xx: 06xx chip 3, write-only
u_n54xx : namco_54xx
port map(
	clk         => clock_18,
	ena         => mcu_ena,
	reset_n     => mcu_reset_n,
	chip_sel    => n06_chipsel_g(3),
	wr_en       => n06_chip_wr_g(3),
	wr_data     => n06_chip_dout,
	discrete_o0 => n54_o0_w,
	discrete_o1 => n54_o1_w,
	discrete_r1 => n54_r1_w,
	rom_wr      => mcu_rom_wr,
	rom_addr_in => mcu_rom_addr,
	rom_data_in => mcu_rom_data
);

-- 52xx: 06xx chip 2, write-only; voice ROM via sample52_*
u_n52xx : namco_52xx
port map(
	clk         => clock_18,
	ena         => mcu_ena,
	reset_n     => mcu_reset_n,
	chip_sel    => n06_chipsel_g(2),
	wr_en       => n06_chip_wr_g(2),
	wr_data     => n06_chip_dout,
	discrete_p  => n52_p_w,
	sample_addr => n52_sample_addr,
	sample_data => sample52_data,
	rom_wr      => mcu_rom_wr,
	rom_addr_in => mcu_rom_addr,
	rom_data_in => mcu_rom_data
);

process (clock_18)
begin
	if rising_edge(clock_18) then
		video_r <= bru_r;
		video_g <= bru_g;
		video_b <= bru_b;
	end if;
end process;

end struct;
