// SPDX-License-Identifier: GPL-2.0
/*
 * Bring-up sound card for the OnePlus 13 (dodge) without a DT change.
 *
 * Registers one DPCM back end, Secondary MI2S RX (the speaker amplifiers'
 * I2S bus), on the q6apm AudioReach platform. The front ends come from the
 * topology, qcom/sm8750/OnePlus-dodge-tplg.bin. The codec is the ASoC dummy,
 * or with amps=1 the two aw882308 amplifiers (left 0x34, right 0x35). This is a stand-in for a
 * "qcom,sm8750-sndcard" node and goes away once the DTB has one.
 *
 * pins=1 also maps TLMM gpio121-124 to i2s1 (sck, data0, ws, data1) as
 * stock does, so the bus reaches the amplifiers during playback.
 */
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/pinctrl/machine.h>
#include <linux/pinctrl/consumer.h>
#include <sound/soc.h>
#include <sound/pcm_params.h>

#define DRV "omamobile-dodge-snd"

static bool pins;
module_param(pins, bool, 0444);
MODULE_PARM_DESC(pins, "mux TLMM gpio121-124 to i2s1 for playback");

static bool amps;
module_param(amps, bool, 0444);
MODULE_PARM_DESC(amps, "use the aw882308 amplifiers (1-0034, 1-0035) as codecs");

static char *tlmm = "f100000.pinctrl";
module_param(tlmm, charp, 0444);

static struct pinctrl_map i2s1_map[] = {
	PIN_MAP_MUX_GROUP(DRV, PINCTRL_STATE_DEFAULT, NULL, "gpio121", "i2s1_sck"),
	PIN_MAP_MUX_GROUP(DRV, PINCTRL_STATE_DEFAULT, NULL, "gpio122", "i2s1_data0"),
	PIN_MAP_MUX_GROUP(DRV, PINCTRL_STATE_DEFAULT, NULL, "gpio123", "i2s1_ws"),
	PIN_MAP_MUX_GROUP(DRV, PINCTRL_STATE_DEFAULT, NULL, "gpio124", "i2s1_data1"),
};

static int dodge_be_fixup(struct snd_soc_pcm_runtime *rtd,
			  struct snd_pcm_hw_params *params)
{
	hw_param_interval(params, SNDRV_PCM_HW_PARAM_RATE)->min = 48000;
	hw_param_interval(params, SNDRV_PCM_HW_PARAM_RATE)->max = 48000;
	hw_param_interval(params, SNDRV_PCM_HW_PARAM_CHANNELS)->min = 2;
	hw_param_interval(params, SNDRV_PCM_HW_PARAM_CHANNELS)->max = 2;
	snd_mask_none(hw_param_mask(params, SNDRV_PCM_HW_PARAM_FORMAT));
	snd_mask_set_format(hw_param_mask(params, SNDRV_PCM_HW_PARAM_FORMAT),
			    SNDRV_PCM_FORMAT_S16_LE);
	return 0;
}

SND_SOC_DAILINK_DEFS(sec_mi2s,
	DAILINK_COMP_ARRAY(COMP_CPU("SEC_MI2S_RX")),
	DAILINK_COMP_ARRAY(COMP_DUMMY()),
	DAILINK_COMP_ARRAY(COMP_PLATFORM("gprsvc:service:2:1")));

static struct snd_soc_dai_link_component dodge_amps[] = {
	{ .name = "aw882308.1-0034", .dai_name = "aw882308-aif" },
	{ .name = "aw882308.1-0035", .dai_name = "aw882308-aif" },
};

static struct snd_soc_codec_conf dodge_amp_conf[] = {
	{ .dlc = COMP_CODEC_CONF("aw882308.1-0034"), .name_prefix = "Left" },
	{ .dlc = COMP_CODEC_CONF("aw882308.1-0035"), .name_prefix = "Right" },
};

static struct snd_soc_dai_link dodge_links[] = {
	{
		.name = "Speaker Playback",
		.stream_name = "Speaker Playback",
		.id = 18, /* SECONDARY_MI2S_RX */
		.no_pcm = 1,
		.playback_only = 1,
		.ignore_pmdown_time = 1,
		.ignore_suspend = 1,
		.nonatomic = 1,
		.dai_fmt = SND_SOC_DAIFMT_I2S | SND_SOC_DAIFMT_NB_NF |
			   SND_SOC_DAIFMT_BC_FC, /* codec consumer: the CPU drives BCLK and WS */
		.be_hw_params_fixup = dodge_be_fixup,
		SND_SOC_DAILINK_REG(sec_mi2s),
	},
};

static struct snd_soc_card dodge_card = {
	.name = "OnePlus-dodge",
	.driver_name = "sm8750",
	.owner = THIS_MODULE,
	.dai_link = dodge_links,
	.num_links = ARRAY_SIZE(dodge_links),
};

static int dodge_snd_probe(struct platform_device *pdev)
{
	dodge_card.dev = &pdev->dev;
	if (amps) {
		dodge_links[0].codecs = dodge_amps;
		dodge_links[0].num_codecs = ARRAY_SIZE(dodge_amps);
		dodge_card.codec_conf = dodge_amp_conf;
		dodge_card.num_configs = ARRAY_SIZE(dodge_amp_conf);
	}
	return devm_snd_soc_register_card(&pdev->dev, &dodge_card);
}

static struct platform_driver dodge_snd_driver = {
	.driver = { .name = DRV },
	.probe = dodge_snd_probe,
};

static struct platform_device *dodge_pdev;

static int __init dodge_snd_init(void)
{
	int i, ret;

	if (pins) {
		for (i = 0; i < ARRAY_SIZE(i2s1_map); i++)
			i2s1_map[i].ctrl_dev_name = tlmm;
		ret = pinctrl_register_mappings(i2s1_map, ARRAY_SIZE(i2s1_map));
		if (ret)
			return ret;
	}

	ret = platform_driver_register(&dodge_snd_driver);
	if (ret)
		goto err_map;

	dodge_pdev = platform_device_register_simple(DRV, -1, NULL, 0);
	if (IS_ERR(dodge_pdev)) {
		ret = PTR_ERR(dodge_pdev);
		platform_driver_unregister(&dodge_snd_driver);
		goto err_map;
	}
	return 0;

err_map:
	if (pins)
		pinctrl_unregister_mappings(i2s1_map);
	return ret;
}

static void __exit dodge_snd_exit(void)
{
	platform_device_unregister(dodge_pdev);
	platform_driver_unregister(&dodge_snd_driver);
	if (pins)
		pinctrl_unregister_mappings(i2s1_map);
}

module_init(dodge_snd_init);
module_exit(dodge_snd_exit);
MODULE_DESCRIPTION("OnePlus 13 bring-up sound card (Secondary MI2S on q6apm)");
MODULE_LICENSE("GPL");
