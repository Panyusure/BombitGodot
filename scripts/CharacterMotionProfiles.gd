extends RefCounted

## Per-character source-space bindings; no texture changes.
const PROFILES = {
  "xiaonuo": {
    "name": "小诺",
    "style": "轻盈跳步 · 晶尾摆动",
    "stride": 12.6,
    "bob": 3.4,
    "sway": 1.5,
    "roll": 0.016,
    "secondary_rate": 0.78,
    "idle_strength": 0.32,
    "front": {
      "size": [
        315,
        560
      ],
      "body_root": [
        170,
        367
      ],
      "legs": [
        {
          "root": [
            139,
            348
          ],
          "foot": [
            166,
            418
          ],
          "radius": 25,
          "lift": 13,
          "forward": [
            7,
            2
          ]
        },
        {
          "root": [
            195,
            348
          ],
          "foot": [
            228,
            376
          ],
          "radius": 16,
          "lift": 10,
          "forward": [
            6,
            2
          ]
        }
      ],
      "parts": [
        {
          "name": "晶尾",
          "root": [
            121,
            387
          ],
          "polygon": [
            [
              0,
              349
            ],
            [
              77,
              349
            ],
            [
              124,
              379
            ],
            [
              132,
              422
            ],
            [
              244,
              560
            ],
            [
              0,
              560
            ]
          ],
          "angle": 0.065,
          "clock": "secondary",
          "lag": -0.6,
          "feather": 22
        },
        {
          "name": "前臂",
          "root": [
            119,
            324
          ],
          "polygon": [
            [
              60,
              246
            ],
            [
              117,
              246
            ],
            [
              142,
              319
            ],
            [
              116,
              350
            ],
            [
              62,
              313
            ]
          ],
          "angle": 0.055,
          "clock": "gait",
          "lag": 3.14,
          "feather": 20
        }
      ],
      "protected_face": [
        115,
        192,
        181,
        120
      ]
    },
    "back": {
      "size": [
        326,
        560
      ],
      "body_root": [
        157,
        359
      ],
      "legs": [
        {
          "root": [
            161,
            365
          ],
          "foot": [
            153,
            425
          ],
          "radius": 22,
          "lift": 13,
          "forward": [
            5,
            2
          ]
        },
        {
          "root": [
            117,
            346
          ],
          "foot": [
            106,
            376
          ],
          "radius": 17,
          "lift": 9,
          "forward": [
            5,
            2
          ]
        }
      ],
      "parts": [
        {
          "name": "晶尾",
          "root": [
            159,
            370
          ],
          "polygon": [
            [
              163,
              356
            ],
            [
              326,
              346
            ],
            [
              326,
              560
            ],
            [
              87,
              560
            ],
            [
              139,
              457
            ],
            [
              192,
              404
            ]
          ],
          "angle": -0.065,
          "clock": "secondary",
          "lag": -0.6,
          "feather": 21
        },
        {
          "name": "手臂",
          "root": [
            130,
            304
          ],
          "polygon": [
            [
              70,
              284
            ],
            [
              140,
              280
            ],
            [
              133,
              338
            ],
            [
              70,
              353
            ]
          ],
          "angle": -0.045,
          "clock": "gait",
          "lag": 3.14,
          "feather": 20
        }
      ],
      "protected_face": [
        43,
        126,
        261,
        164
      ]
    }
  },
  "axiu": {
    "name": "阿修",
    "style": "紧凑快步 · 闪电尾回摆",
    "stride": 13.2,
    "bob": 1.7,
    "sway": 1.0,
    "roll": 0.012,
    "secondary_rate": 1.12,
    "idle_strength": 0.22,
    "front": {
      "size": [
        390,
        560
      ],
      "body_root": [
        213,
        403
      ],
      "legs": [
        {
          "root": [
            220,
            413
          ],
          "foot": [
            198,
            474
          ],
          "radius": 23,
          "lift": 11,
          "forward": [
            5,
            2
          ]
        },
        {
          "root": [
            261,
            399
          ],
          "foot": [
            262,
            442
          ],
          "radius": 17,
          "lift": 9,
          "forward": [
            4,
            1.5
          ]
        }
      ],
      "parts": [
        {
          "name": "闪电尾",
          "root": [
            181,
            447
          ],
          "polygon": [
            [
              0,
              396
            ],
            [
              108,
              388
            ],
            [
              179,
              418
            ],
            [
              218,
              447
            ],
            [
              223,
              560
            ],
            [
              0,
              560
            ]
          ],
          "angle": 0.055,
          "clock": "secondary",
          "lag": -0.9,
          "feather": 24
        },
        {
          "name": "护臂",
          "root": [
            176,
            363
          ],
          "polygon": [
            [
              119,
              343
            ],
            [
              171,
              337
            ],
            [
              193,
              374
            ],
            [
              160,
              399
            ],
            [
              113,
              385
            ]
          ],
          "angle": 0.04,
          "clock": "gait",
          "lag": 3.14,
          "feather": 20
        }
      ],
      "protected_face": [
        162,
        228,
        198,
        120
      ]
    },
    "back": {
      "size": [
        389,
        560
      ],
      "body_root": [
        193,
        393
      ],
      "legs": [
        {
          "root": [
            175,
            407
          ],
          "foot": [
            175,
            461
          ],
          "radius": 22,
          "lift": 11,
          "forward": [
            5,
            2
          ]
        },
        {
          "root": [
            225,
            384
          ],
          "foot": [
            238,
            423
          ],
          "radius": 16,
          "lift": 9,
          "forward": [
            5,
            1.5
          ]
        }
      ],
      "parts": [
        {
          "name": "闪电尾",
          "root": [
            222,
            410
          ],
          "polygon": [
            [
              211,
              391
            ],
            [
              268,
              392
            ],
            [
              304,
              439
            ],
            [
              389,
              447
            ],
            [
              389,
              560
            ],
            [
              165,
              560
            ],
            [
              183,
              473
            ],
            [
              206,
              435
            ]
          ],
          "angle": -0.055,
          "clock": "secondary",
          "lag": -0.9,
          "feather": 25
        },
        {
          "name": "护臂",
          "root": [
            143,
            353
          ],
          "polygon": [
            [
              101,
              330
            ],
            [
              147,
              325
            ],
            [
              170,
              363
            ],
            [
              140,
              402
            ],
            [
              102,
              396
            ]
          ],
          "angle": -0.035,
          "clock": "gait",
          "lag": 3.14,
          "feather": 20
        }
      ],
      "protected_face": [
        46,
        102,
        300,
        222
      ]
    }
  },
  "arui": {
    "name": "阿瑞",
    "style": "沉稳短步 · 叶片披摆",
    "stride": 8.6,
    "bob": 2.0,
    "sway": 2.2,
    "roll": 0.02,
    "secondary_rate": 0.57,
    "idle_strength": 0.24,
    "front": {
      "size": [
        446,
        560
      ],
      "body_root": [
        224,
        429
      ],
      "legs": [
        {
          "root": [
            191,
            476
          ],
          "foot": [
            168,
            540
          ],
          "radius": 22,
          "lift": 8,
          "forward": [
            5,
            1.5
          ]
        },
        {
          "root": [
            287,
            463
          ],
          "foot": [
            304,
            502
          ],
          "radius": 18,
          "lift": 7,
          "forward": [
            4,
            1.5
          ]
        }
      ],
      "parts": [
        {
          "name": "左叶摆",
          "root": [
            117,
            370
          ],
          "polygon": [
            [
              0,
              308
            ],
            [
              91,
              303
            ],
            [
              152,
              399
            ],
            [
              162,
              532
            ],
            [
              0,
              560
            ]
          ],
          "angle": 0.04,
          "clock": "secondary",
          "lag": -0.55,
          "feather": 24
        },
        {
          "name": "右叶摆",
          "root": [
            291,
            380
          ],
          "polygon": [
            [
              309,
              363
            ],
            [
              412,
              357
            ],
            [
              446,
              512
            ],
            [
              322,
              538
            ],
            [
              301,
              463
            ]
          ],
          "angle": -0.034,
          "clock": "secondary",
          "lag": -0.9,
          "feather": 25
        },
        {
          "name": "左臂",
          "root": [
            145,
            371
          ],
          "polygon": [
            [
              25,
              335
            ],
            [
              115,
              327
            ],
            [
              158,
              368
            ],
            [
              125,
              428
            ],
            [
              37,
              450
            ]
          ],
          "angle": 0.03,
          "clock": "gait",
          "lag": 3.14,
          "feather": 20
        },
        {
          "name": "右臂",
          "root": [
            341,
            351
          ],
          "polygon": [
            [
              351,
              226
            ],
            [
              446,
              226
            ],
            [
              446,
              352
            ],
            [
              341,
              380
            ],
            [
              317,
              341
            ]
          ],
          "angle": -0.022,
          "clock": "gait",
          "lag": 0,
          "feather": 20
        }
      ],
      "protected_face": [
        153,
        228,
        213,
        116
      ]
    },
    "back": {
      "size": [
        419,
        560
      ],
      "body_root": [
        212,
        435
      ],
      "legs": [
        {
          "root": [
            156,
            498
          ],
          "foot": [
            139,
            538
          ],
          "radius": 24,
          "lift": 8,
          "forward": [
            4,
            1.5
          ]
        },
        {
          "root": [
            263,
            498
          ],
          "foot": [
            283,
            538
          ],
          "radius": 23,
          "lift": 8,
          "forward": [
            4,
            1.5
          ]
        }
      ],
      "parts": [
        {
          "name": "左叶摆",
          "root": [
            125,
            363
          ],
          "polygon": [
            [
              0,
              352
            ],
            [
              118,
              346
            ],
            [
              197,
              458
            ],
            [
              178,
              533
            ],
            [
              0,
              551
            ]
          ],
          "angle": 0.038,
          "clock": "secondary",
          "lag": -0.55,
          "feather": 25
        },
        {
          "name": "右叶摆",
          "root": [
            291,
            362
          ],
          "polygon": [
            [
              304,
              345
            ],
            [
              419,
              345
            ],
            [
              419,
              548
            ],
            [
              245,
              536
            ],
            [
              222,
              459
            ]
          ],
          "angle": -0.038,
          "clock": "secondary",
          "lag": -0.9,
          "feather": 25
        },
        {
          "name": "左臂",
          "root": [
            104,
            356
          ],
          "polygon": [
            [
              0,
              311
            ],
            [
              100,
              311
            ],
            [
              124,
              365
            ],
            [
              97,
              419
            ],
            [
              0,
              428
            ]
          ],
          "angle": -0.024,
          "clock": "gait",
          "lag": 3.14,
          "feather": 20
        },
        {
          "name": "右臂",
          "root": [
            312,
            356
          ],
          "polygon": [
            [
              319,
              311
            ],
            [
              419,
              311
            ],
            [
              419,
              431
            ],
            [
              319,
              420
            ],
            [
              297,
              367
            ]
          ],
          "angle": 0.024,
          "clock": "gait",
          "lag": 0,
          "feather": 20
        }
      ],
      "protected_face": [
        46,
        85,
        328,
        232
      ]
    }
  },
  "xiaoyan": {
    "name": "小炎",
    "style": "蓄力快步 · 鬃尾跟随",
    "stride": 13.6,
    "bob": 3.8,
    "sway": 1.7,
    "roll": 0.018,
    "secondary_rate": 1.28,
    "idle_strength": 0.3,
    "front": {
      "size": [
        443,
        560
      ],
      "body_root": [
        282,
        429
      ],
      "legs": [
        {
          "root": [
            253,
            468
          ],
          "foot": [
            263,
            530
          ],
          "radius": 24,
          "lift": 15,
          "forward": [
            9,
            2.8
          ]
        },
        {
          "root": [
            326,
            437
          ],
          "foot": [
            341,
            487
          ],
          "radius": 20,
          "lift": 12,
          "forward": [
            7,
            2.5
          ]
        }
      ],
      "parts": [
        {
          "name": "烈焰鬃尾",
          "root": [
            205,
            351
          ],
          "polygon": [
            [
              0,
              327
            ],
            [
              158,
              311
            ],
            [
              211,
              340
            ],
            [
              213,
              402
            ],
            [
              172,
              514
            ],
            [
              0,
              560
            ]
          ],
          "angle": 0.055,
          "clock": "secondary",
          "lag": -0.7,
          "feather": 25
        },
        {
          "name": "左焰甲",
          "root": [
            242,
            416
          ],
          "polygon": [
            [
              153,
              359
            ],
            [
              229,
              368
            ],
            [
              280,
              433
            ],
            [
              247,
              495
            ],
            [
              159,
              491
            ]
          ],
          "angle": 0.035,
          "clock": "gait",
          "lag": 3.14,
          "feather": 20
        },
        {
          "name": "右焰甲",
          "root": [
            357,
            412
          ],
          "polygon": [
            [
              357,
              353
            ],
            [
              415,
              346
            ],
            [
              443,
              448
            ],
            [
              390,
              490
            ],
            [
              356,
              451
            ]
          ],
          "angle": -0.028,
          "clock": "gait",
          "lag": 0,
          "feather": 20
        }
      ],
      "protected_face": [
        241,
        242,
        183,
        107
      ]
    },
    "back": {
      "size": [
        405,
        560
      ],
      "body_root": [
        254,
        408
      ],
      "legs": [
        {
          "root": [
            265,
            453
          ],
          "foot": [
            269,
            497
          ],
          "radius": 23,
          "lift": 10,
          "forward": [
            4,
            1.5
          ]
        },
        {
          "root": [
            326,
            403
          ],
          "foot": [
            333,
            449
          ],
          "radius": 18,
          "lift": 8,
          "forward": [
            4.5,
            1.5
          ]
        }
      ],
      "parts": [
        {
          "name": "烈焰鬃尾",
          "root": [
            239,
            327
          ],
          "polygon": [
            [
              0,
              300
            ],
            [
              184,
              293
            ],
            [
              260,
              314
            ],
            [
              274,
              399
            ],
            [
              230,
              511
            ],
            [
              139,
              560
            ],
            [
              0,
              560
            ]
          ],
          "angle": 0.035,
          "clock": "secondary",
          "lag": -0.7,
          "feather": 28
        },
        {
          "name": "左焰甲",
          "root": [
            123,
            365
          ],
          "polygon": [
            [
              59,
              302
            ],
            [
              125,
              295
            ],
            [
              178,
              362
            ],
            [
              154,
              427
            ],
            [
              52,
              423
            ]
          ],
          "angle": 0.03,
          "clock": "gait",
          "lag": 3.14,
          "feather": 20
        },
        {
          "name": "右焰甲",
          "root": [
            332,
            364
          ],
          "polygon": [
            [
              329,
              292
            ],
            [
              395,
              304
            ],
            [
              405,
              433
            ],
            [
              333,
              431
            ],
            [
              302,
              363
            ]
          ],
          "angle": -0.03,
          "clock": "gait",
          "lag": 0,
          "feather": 20
        }
      ],
      "protected_face": [
        94,
        90,
        233,
        209
      ]
    }
  },
  "xiaotian": {
    "name": "小天",
    "style": "轻踏滑行 · 羽尾浮动",
    "stride": 8.4,
    "bob": 1.4,
    "sway": 1.1,
    "roll": 0.009,
    "secondary_rate": 0.66,
    "idle_strength": 0.42,
    "front": {
      "size": [
        572,
        560
      ],
      "body_root": [
        365,
        398
      ],
      "legs": [
        {
          "root": [
            316,
            421
          ],
          "foot": [
            291,
            478
          ],
          "radius": 30,
          "lift": 8,
          "forward": [
            5,
            1.5
          ]
        },
        {
          "root": [
            419,
            412
          ],
          "foot": [
            437,
            463
          ],
          "radius": 27,
          "lift": 7,
          "forward": [
            5,
            1.5
          ]
        }
      ],
      "parts": [
        {
          "name": "羽尾",
          "root": [
            121,
            416
          ],
          "polygon": [
            [
              0,
              363
            ],
            [
              106,
              366
            ],
            [
              161,
              422
            ],
            [
              170,
              478
            ],
            [
              248,
              521
            ],
            [
              245,
              560
            ],
            [
              0,
              560
            ]
          ],
          "angle": 0.045,
          "clock": "secondary",
          "lag": -0.75,
          "feather": 28
        },
        {
          "name": "蓝色发梢",
          "root": [
            285,
            169
          ],
          "polygon": [
            [
              0,
              66
            ],
            [
              154,
              58
            ],
            [
              249,
              142
            ],
            [
              231,
              264
            ],
            [
              179,
              385
            ],
            [
              0,
              414
            ]
          ],
          "angle": 0.014,
          "clock": "secondary",
          "lag": -1.15,
          "feather": 30
        },
        {
          "name": "左羽摆",
          "root": [
            292,
            385
          ],
          "polygon": [
            [
              157,
              359
            ],
            [
              262,
              352
            ],
            [
              322,
              405
            ],
            [
              250,
              479
            ],
            [
              148,
              469
            ]
          ],
          "angle": 0.021,
          "clock": "gait",
          "lag": 3.14,
          "feather": 20
        },
        {
          "name": "右羽摆",
          "root": [
            440,
            377
          ],
          "polygon": [
            [
              459,
              347
            ],
            [
              572,
              355
            ],
            [
              572,
              469
            ],
            [
              458,
              470
            ],
            [
              430,
              416
            ]
          ],
          "angle": -0.02,
          "clock": "gait",
          "lag": 0,
          "feather": 20
        }
      ],
      "protected_face": [
        304,
        214,
        250,
        116
      ]
    },
    "back": {
      "size": [
        532,
        560
      ],
      "body_root": [
        234,
        400
      ],
      "legs": [
        {
          "root": [
            178,
            436
          ],
          "foot": [
            166,
            487
          ],
          "radius": 28,
          "lift": 8,
          "forward": [
            4,
            1.5
          ]
        },
        {
          "root": [
            278,
            435
          ],
          "foot": [
            289,
            487
          ],
          "radius": 27,
          "lift": 7,
          "forward": [
            4,
            1.5
          ]
        }
      ],
      "parts": [
        {
          "name": "羽尾",
          "root": [
            387,
            442
          ],
          "polygon": [
            [
              425,
              375
            ],
            [
              532,
              402
            ],
            [
              532,
              560
            ],
            [
              317,
              560
            ],
            [
              335,
              496
            ],
            [
              379,
              461
            ]
          ],
          "angle": -0.045,
          "clock": "secondary",
          "lag": -0.75,
          "feather": 29
        },
        {
          "name": "蓝色发梢",
          "root": [
            229,
            157
          ],
          "polygon": [
            [
              161,
              45
            ],
            [
              442,
              48
            ],
            [
              532,
              183
            ],
            [
              532,
              383
            ],
            [
              399,
              401
            ],
            [
              313,
              313
            ]
          ],
          "angle": -0.012,
          "clock": "secondary",
          "lag": -1.15,
          "feather": 30
        },
        {
          "name": "左羽摆",
          "root": [
            171,
            359
          ],
          "polygon": [
            [
              0,
              345
            ],
            [
              149,
              332
            ],
            [
              206,
              399
            ],
            [
              169,
              491
            ],
            [
              0,
              484
            ]
          ],
          "angle": 0.022,
          "clock": "gait",
          "lag": 3.14,
          "feather": 20
        },
        {
          "name": "右羽摆",
          "root": [
            294,
            358
          ],
          "polygon": [
            [
              307,
              336
            ],
            [
              435,
              335
            ],
            [
              458,
              483
            ],
            [
              296,
              495
            ],
            [
              266,
              411
            ]
          ],
          "angle": -0.021,
          "clock": "gait",
          "lag": 0,
          "feather": 20
        }
      ],
      "protected_face": [
        102,
        101,
        267,
        202
      ]
    }
  }
}
