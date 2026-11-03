// SPDX-License-Identifier: GPL-2.0
/*
 * One gamepad from GPIO buttons and ADC sticks, polled together. Buttons are described as for
 * gpio-keys and axes as for adc-joystick. A button without gpios is only declared, which keeps
 * another gamepad's button numbering (the R36H has no FN, the GA36-MB does).
 */
#include <linux/gpio/consumer.h>
#include <linux/iio/consumer.h>
#include <linux/input.h>
#include <linux/mod_devicetable.h>
#include <linux/module.h>
#include <linux/platform_device.h>
#include <linux/property.h>

struct gamepad_button {
    struct gpio_desc *gpio;
    unsigned int code;
};

struct gamepad_axis {
    struct iio_channel *chan;
    unsigned int code;
    s32 min, max;
    bool inverted;
};

struct gamepad {
    struct gamepad_button *buttons;
    struct gamepad_axis *axes;
    int nbuttons, naxes;
};

static void gamepad_poll(struct input_dev *idev)
{
    struct gamepad *gp = input_get_drvdata(idev);
    int i, val;

    for (i = 0; i < gp->nbuttons; i++)
        if (gp->buttons[i].gpio)
            input_report_key(idev, gp->buttons[i].code, gpiod_get_value_cansleep(gp->buttons[i].gpio) > 0);

    for (i = 0; i < gp->naxes; i++) {
        struct gamepad_axis *a = &gp->axes[i];

        if (iio_read_channel_raw(a->chan, &val) < 0)
            continue;
        input_report_abs(idev, a->code, a->inverted ? a->min + a->max - val : val);
    }
    input_sync(idev);
}

static int gamepad_add_axis(struct device *dev, struct fwnode_handle *child, struct gamepad *gp,
                            struct iio_channel *chans, int nchans)
{
    struct gamepad_axis *a = &gp->axes[gp->naxes];
    u32 reg, range[2];
    int err;

    err = fwnode_property_read_u32(child, "reg", &reg);
    if (err || reg >= nchans)
        return dev_err_probe(dev, -EINVAL, "%pfwP: no ADC channel\n", child);
    err = fwnode_property_read_u32(child, "linux,code", &a->code);
    if (err)
        return dev_err_probe(dev, err, "%pfwP: no linux,code\n", child);
    err = fwnode_property_read_u32_array(child, "abs-range", range, 2);
    if (err)
        return dev_err_probe(dev, err, "%pfwP: no abs-range\n", child);

    a->chan = &chans[reg];
    a->inverted = range[0] > range[1];
    a->min = min(range[0], range[1]);
    a->max = max(range[0], range[1]);
    gp->naxes++;
    return 0;
}

static int gamepad_add_button(struct device *dev, struct fwnode_handle *child, struct gamepad *gp)
{
    struct gamepad_button *b = &gp->buttons[gp->nbuttons];
    int err;

    err = fwnode_property_read_u32(child, "linux,code", &b->code);
    if (err)
        return dev_err_probe(dev, err, "%pfwP: no linux,code\n", child);
    b->gpio = devm_fwnode_gpiod_get_optional(dev, child, NULL, GPIOD_IN, NULL);
    if (IS_ERR(b->gpio))
        return dev_err_probe(dev, PTR_ERR(b->gpio), "%pfwP: bad gpios\n", child);
    gp->nbuttons++;
    return 0;
}

static int gamepad_probe(struct platform_device *pdev)
{
    struct device *dev = &pdev->dev;
    struct iio_channel *chans;
    struct input_dev *idev;
    struct gamepad *gp;
    const char *name = "Gamepad";
    u32 poll = 16, fuzz, flat;
    int nchans = 0, count, i, err;

    gp = devm_kzalloc(dev, sizeof(*gp), GFP_KERNEL);
    if (!gp)
        return -ENOMEM;

    chans = devm_iio_channel_get_all(dev);
    if (IS_ERR(chans)) {
        if (PTR_ERR(chans) != -ENODEV)
            return dev_err_probe(dev, PTR_ERR(chans), "Unable to get the ADC channels\n");
        chans = NULL;
    }
    while (chans && chans[nchans].indio_dev)
        nchans++;

    count = device_get_child_node_count(dev);
    gp->buttons = devm_kcalloc(dev, count, sizeof(*gp->buttons), GFP_KERNEL);
    gp->axes = devm_kcalloc(dev, count, sizeof(*gp->axes), GFP_KERNEL);
    if (!gp->buttons || !gp->axes)
        return -ENOMEM;

    device_for_each_child_node_scoped(dev, child) {
        if (fwnode_name_eq(child, "axis"))
            err = gamepad_add_axis(dev, child, gp, chans, nchans);
        else
            err = gamepad_add_button(dev, child, gp);
        if (err)
            return err;
    }

    idev = devm_input_allocate_device(dev);
    if (!idev)
        return -ENOMEM;

    device_property_read_string(dev, "label", &name);
    idev->name = name;
    idev->id.bustype = BUS_HOST;
    input_set_drvdata(idev, gp);

    for (i = 0; i < gp->nbuttons; i++)
        input_set_capability(idev, EV_KEY, gp->buttons[i].code);

    i = 0;
    device_for_each_child_node_scoped(dev, child) {
        if (!fwnode_name_eq(child, "axis"))
            continue;
        fuzz = flat = 0;
        fwnode_property_read_u32(child, "abs-fuzz", &fuzz);
        fwnode_property_read_u32(child, "abs-flat", &flat);
        input_set_abs_params(idev, gp->axes[i].code, gp->axes[i].min, gp->axes[i].max, fuzz, flat);
        i++;
    }

    device_property_read_u32(dev, "poll-interval", &poll);
    err = input_setup_polling(idev, gamepad_poll);
    if (err)
        return err;
    input_set_poll_interval(idev, poll);

    return input_register_device(idev);
}

static const struct of_device_id gamepad_of_match[] = {
    { .compatible = "gameconsole,gpio-adc-gamepad" },
    { }
};
MODULE_DEVICE_TABLE(of, gamepad_of_match);

static struct platform_driver gamepad_driver = {
    .probe = gamepad_probe,
    .driver = {
        .name = "gpio-adc-gamepad",
        .of_match_table = gamepad_of_match,
    },
};
module_platform_driver(gamepad_driver);

MODULE_DESCRIPTION("Gamepad from GPIO buttons and ADC sticks");
MODULE_LICENSE("GPL");
