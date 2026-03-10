#!/usr/bin/env python3
"""
Скрипт для построения графиков по логам волн (сводка из game_manager).
Запуск: python plot_wave_logs.py [файл]
  Без аргумента — данные из TABLE_ROWS в скрипте.
  С аргументом — первая строка файла = заголовок (таб), остальные = строки данных.
  Пример: python plot_wave_logs.py wave_log.txt
Требует: matplotlib, numpy (pip install matplotlib numpy)
"""

import sys
import os
import matplotlib.pyplot as plt
import matplotlib.ticker as ticker
import numpy as np

# Данные из лога [Сводка волн для графика] (таб-разделители). путь_гексов = длина пути в гексах.
# Руда: руда_трат=за раунд, руда_сек=руда/сек, руда_доб=добыто, майнер_гексов=гексов майнерами, руда_центр/серед/конец=траты по секторам.
# В конце: hp_игрока, lvl_игрока, xp_всего, пропущено_врагов, руда_всего (накопительно), успех (уровень успеха, число 6+, ср. 10).
TABLE_HEADER = "волна	длит_игр	длит_реал	врагов	путь_гексов	путь_макс%	путь_ср%	руда_трат	руда_сек	руда_доб	майнер_гексов	руда_центр	руда_серед	руда_конец	до_0	до_1	до_2	до_3	до_4	до_5	0->1	1->2	2->3	3->4	4->5	hp_игрока	lvl_игрока	xp_всего	пропущено_врагов	руда_всего	успех"
# Данные по умолчанию: прогон до волны 27 (пользовательский лог)
TABLE_ROWS = """
1	59.6	15.6	5	130	86	78	1	0.1	0	1	1	0	0	100	100	100	80	80	0	12.8	5.9	12.3	5.9	0.0	100	1	50	0	1	1
2	43.6	10.9	9	133	57	54	2	0.1	1	2	2	0	0	100	100	100	0	0	0	12.8	5.9	0.0	0.0	0.0	100	1	140	0	4	1
3	43.6	10.9	10	136	53	31	2	0.2	2	3	2	0	0	100	10	10	0	0	0	12.8	5.9	0.0	0.0	0.0	100	1	240	0	11	1
4	60.7	15.2	9	146	85	42	7	0.5	3	4	7	0	0	100	33	33	11	11	0	12.4	7.7	11.3	5.5	0.0	100	1	330	0	18	1
5	25.7	6.4	12	148	26	15	6	0.9	4	5	6	0	0	8	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	1	450	0	29	1
6	29.6	7.4	14	152	26	15	8	1.1	5	5	8	0	0	14	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	2	590	0	38	1
7	33.4	8.4	14	158	26	20	11	1.3	5	5	11	0	0	57	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	2	730	0	49	1
8	44.9	11.2	19	165	83	25	11	1.0	5	5	11	0	0	63	11	11	5	5	0	7.6	6.7	6.5	3.0	0.0	100	2	920	0	60	1
9	28.2	7.0	42	174	12	11	29	4.1	5	4	19	0	10	0	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	2	1340	0	89	1
10	120.6	31.5	1	178	80	80	39	1.2	4	4	39	0	0	100	100	100	100	100	0	34.0	15.1	15.3	6.7	0.0	100	2	1350	0	128	1
11	25.0	6.2	22	185	11	10	24	3.8	5	5	15	4	5	0	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	2	1570	0	152	1
12	90.0	22.5	19	192	78	47	45	2.0	6	6	25	20	0	100	63	58	26	26	0	14.9	13.5	13.8	9.2	0.0	100	2	1760	0	197	1
13	17.2	4.3	22	196	11	10	10	2.3	8	7	0	10	0	0	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	2	1980	0	207	1
14	35.2	8.8	35	201	22	17	19	2.2	10	8	0	19	0	29	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	2	2330	0	226	1
15	28.9	7.2	20	124	23	22	11	1.5	12	9	0	11	0	100	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	3	2530	0	237	1
16	24.6	6.2	27	219	10	9	12	1.9	13	9	0	12	0	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	3	2800	0	248	1
17	39.7	9.9	25	124	53	27	13	1.4	13	9	0	13	0	100	12	12	0	0	0	11.7	5.9	0.0	0.0	0.0	100	3	3050	0	262	1
18	25.2	6.3	21	239	9	9	10	1.6	13	9	0	10	0	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	3	3260	0	272	1
19	57.3	14.3	53	245	25	17	27	1.9	13	9	0	27	0	43	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	3	3790	0	302	1
20	154.9	51.1	1	245	80	80	50	1.0	13	8	18	27	5	100	100	100	100	100	0	44.0	17.0	24.8	11.1	0.0	100	3	3800	0	352	1
21	74.2	18.5	26	253	25	14	46	2.5	15	9	24	13	9	31	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	100	3	4060	0	398	1
22	118.8	29.7	24	279	100	63	59	2.0	19	10	38	16	5	79	71	63	50	42	4	0.0	14.6	12.7	12.7	14.1	96	3	4290	1	456	1
23	128.8	98.5	28	309	92	54	101	1.0	20	11	57	39	5	93	68	64	50	32	4	22.8	18.5	13.7	17.7	19.4	96	4	4570	1	558	1
24	37.8	35.7	26	317	43	19	30	0.9	20	12	3	19	9	58	12	0	0	0	0	14.9	0.0	0.0	0.0	0.0	96	4	4830	1	591	1
25	37.2	12.3	28	124	53	25	12	0.9	20	13	1	10	0	100	7	7	0	0	0	11.1	5.5	0.0	0.0	0.0	96	4	5110	1	603	1
26	51.3	12.8	32	335	20	14	24	1.9	18	13	1	23	0	44	0	0	0	0	0	0.0	0.0	0.0	0.0	0.0	96	4	5430	1	627	1
27	175.0	43.7	42	359	100	59	46	1.1	16	13	20	17	9	69	62	62	48	48	48	31.4	25.0	24.2	22.8	16.4	46	4	5650	21	673	1
""".strip()

# Руда по вышкам за раунд (среднее): вышка, def_id, руда_всего, руда_сек.
TOWER_ORE_HEADER = "вышка	def_id	руда_всего	руда_сек"
TOWER_ORE_ROWS = """
Вулкан	TOWER_VOLCANO	106.9	0.07
Грус	TOWER_GRUSS	86.3	0.05
Сильвер Найт	TOWER_SILVER_KNIGHT	72.6	0.05
Сильвер	TOWER_SILVER	51.7	0.03
Маяк	TOWER_LIGHTHOUSE	45.3	0.03
Голд	TOWER_GOLD	31.3	0.02
TE (Маг. атака) Lv.2	TE2	25.0	0.02
TE (Маг. атака) Lv.1	TE1	23.2	0.01
PE (Сплит-маг.) Lv.1	PE1	22.7	0.01
Малахит	TOWER_MALACHITE	22.4	0.01
NE (Снижение маг. брони) Lv.1	NE1	18.4	0.01
Кайлун	TOWER_KAILUN	9.0	0.01
TO (Чист. атака) Lv.3	TO3	9.0	0.01
PE (Сплит-маг.) Lv.2	PE2	7.0	0.00
DE (Аура) Lv.1	DE1	4.8	0.00
NI (Замедление) Lv.1	NI1	3.7	0.00
Рубин	TOWER_RUBY	3.2	0.00
TO (Чист. атака) Lv.2	TO2	2.4	0.00
Стена	TOWER_WALL	1.1	0.00
""".strip()

def parse_table(header_text=None, rows_text=None):
    header = header_text if header_text is not None else TABLE_HEADER
    body = (rows_text if rows_text is not None else TABLE_ROWS).strip()
    COLS_LIST = [c.strip() for c in header.split("\t")]
    rows = []
    for line in body.split("\n"):
        line = line.strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split("\t")]
        # Старый формат: 17 колонок (без путь_гексов и руды); 18 (с путь_гексов); полный 25 (+ руда)
        if "путь_гексов" in COLS_LIST and len(parts) == len(COLS_LIST) - 8:  # 17 колонок -> вставка путь_гексов
            idx = COLS_LIST.index("путь_гексов")
            parts = parts[:idx] + ["0"] + parts[idx:]
        ore_cols = ["руда_трат", "руда_сек", "руда_доб", "майнер_гексов", "руда_центр", "руда_серед", "руда_конец"]
        if all(c in COLS_LIST for c in ore_cols) and len(parts) == len(COLS_LIST) - 7:
            idx = COLS_LIST.index("руда_трат")
            parts = parts[:idx] + ["0"] * 7 + parts[idx:]
        if "путь_гексов" in COLS_LIST and len(parts) == len(COLS_LIST) - 1:
            idx = COLS_LIST.index("путь_гексов")
            parts = parts[:idx] + ["0"] + parts[idx:]
        # Старые логи без колонок hp_игрока, lvl_игрока, xp_всего, пропущено_врагов, руда_всего, успех — дополняем
        while len(parts) < len(COLS_LIST):
            col_name = COLS_LIST[len(parts)] if len(parts) < len(COLS_LIST) else ""
            parts.append("10" if col_name == "успех" else "0")
        if len(parts) > len(COLS_LIST):
            parts = parts[:len(COLS_LIST)]
        row = {}
        for i, col in enumerate(COLS_LIST):
            try:
                row[col] = float(parts[i])
            except ValueError:
                row[col] = parts[i]
        rows.append(row)
    return rows


def parse_tower_ore(header_text=None, rows_text=None):
    """Парсит таблицу [Руда по вышкам за раунд]: вышка, def_id, руда_всего, руда_сек."""
    header = header_text if header_text is not None else TOWER_ORE_HEADER
    body = (rows_text if rows_text is not None else TOWER_ORE_ROWS).strip()
    cols = [c.strip() for c in header.split("\t")]
    rows = []
    for line in body.split("\n"):
        line = line.strip()
        if not line:
            continue
        parts = [p.strip() for p in line.split("\t")]
        if len(parts) < len(cols):
            continue
        row = {}
        for i, col in enumerate(cols):
            try:
                row[col] = float(parts[i])
            except ValueError:
                row[col] = parts[i]
        rows.append(row)
    return rows


def rolling_mean(arr, window=5):
    """Скользящее среднее (средняя линия с изменением по волнам)."""
    n = len(arr)
    out = np.full(n, np.nan)
    for i in range(n):
        lo = max(0, i - window // 2)
        hi = min(n, i + window // 2 + 1)
        out[i] = np.nanmean(arr[lo:hi])
    return out


def style_axes(ax, title=None):
    ax.grid(True, alpha=0.3)
    ax.set_title(title, fontsize=11)
    ax.legend(loc="best", fontsize=8)


def main():
    header_text = None
    rows_text = None
    tower_ore_header_text = None
    tower_ore_rows_text = None
    if len(sys.argv) > 1:
        path = sys.argv[1]
        if os.path.isfile(path):
            with open(path, "r", encoding="utf-8") as f:
                lines = [ln.strip() for ln in f.read().strip().split("\n") if ln.strip()]
            start = 0
            for i, ln in enumerate(lines):
                if "волна" in ln and "\t" in ln:
                    start = i
                    break
            if start < len(lines):
                header_text = lines[start]
                end = start + 1
                for j in range(start + 1, len(lines)):
                    if lines[j].startswith("[") or ("вышка" in lines[j] and "\t" in lines[j] and "волна" not in lines[j]):
                        end = j
                        break
                else:
                    end = len(lines)
                rows_text = "\n".join(lines[start + 1:end])
                print("Загружены данные из %s (%d строк волн)" % (path, end - start - 1))
                for i in range(len(lines)):
                    if "Руда по вышкам" in lines[i]:
                        for j in range(i + 1, len(lines)):
                            if "вышка" in lines[j] and "\t" in lines[j]:
                                tower_ore_header_text = lines[j]
                                ore_end = j + 1
                                while ore_end < len(lines) and not lines[ore_end].startswith("["):
                                    ore_end += 1
                                tower_ore_rows_text = "\n".join(lines[j + 1:ore_end])
                                print("Загружена таблица руда по вышкам (%d строк)" % (ore_end - j - 1))
                                break
                        break
            else:
                print("В файле %s не найден заголовок таблицы (строка с 'волна' и табуляцией)" % path)
                sys.exit(1)
    data = parse_table(header_text=header_text, rows_text=rows_text)
    tower_ore_data = parse_tower_ore(header_text=tower_ore_header_text, rows_text=tower_ore_rows_text)
    print("Загружено волн: %d, вышок в таблице руды: %d" % (len(data), len(tower_ore_data)))
    if len(data) == 0:
        print("Ошибка: нет данных волн. Проверьте формат файла или TABLE_ROWS.")
        sys.exit(1)
    data_30 = [r for r in data if r["волна"] <= 30]
    waves = [r["волна"] for r in data]
    waves_30 = [r["волна"] for r in data_30]
    n = len(waves)
    n30 = len(waves_30)
    window = 5
    x_max = max(waves) + 1 if n > 0 else 35

    plt.rcParams["figure.figsize"] = (12, 10)
    plt.rcParams["font.size"] = 9

    def add_mean_line(ax, arr, label_prefix="Ср. за всё"):
        m = np.nanmean(arr)
        ax.axhline(m, color="gray", linestyle="--", alpha=0.7, linewidth=1.5, label=f"{label_prefix}: {m:.1f}")

    # --- 1. Длительность волны (все волны) + скользящее среднее + среднее за всё ---
    dur_igr = np.array([r["длит_игр"] for r in data])
    dur_real = np.array([r["длит_реал"] for r in data])
    rm_igr = rolling_mean(dur_igr, window)
    rm_real = rolling_mean(dur_real, window)
    fig1, ax1 = plt.subplots(figsize=(12, 5))
    ax1.plot(waves, dur_igr, "o-", color="C0", label="Длительность (игр. с)", markersize=4)
    ax1.plot(waves, rm_igr, "-", color="C0", linewidth=2.5, alpha=0.9, label=f"Скольз. ср. игр. (окно {window})")
    add_mean_line(ax1, dur_igr, "Ср. игр.")
    ax1.plot(waves, dur_real, "s-", color="C1", label="Длительность (реал. с)", markersize=4)
    ax1.plot(waves, rm_real, "-", color="C1", linewidth=2.5, alpha=0.9, label=f"Скольз. ср. реал. (окно {window})")
    add_mean_line(ax1, dur_real, "Ср. реал.")
    ax1.set_xlabel("Номер волны")
    ax1.set_ylabel("Секунды")
    ax1.set_xlim(0, x_max)
    style_axes(ax1, "Длительность волны по волнам (игр. и реал.)")
    fig1.tight_layout()
    fig1.savefig("wave_duration_and_size.png", dpi=120, bbox_inches="tight")
    plt.close(fig1)
    print("Сохранено: wave_duration_and_size.png")

    # --- 2. Размер волны (врагов) + скользящее среднее + среднее ---
    enemies = np.array([r["врагов"] for r in data])
    rm_en = rolling_mean(enemies, window)
    fig1b, ax1b = plt.subplots(figsize=(12, 5))
    ax1b.bar(waves, enemies, color="C2", alpha=0.6, label="Врагов в волне")
    ax1b.plot(waves, rm_en, "o-", color="darkgreen", linewidth=2.5, markersize=5, label=f"Скольз. ср. (окно {window})")
    add_mean_line(ax1b, enemies, "Ср. врагов")
    ax1b.set_xlabel("Номер волны")
    ax1b.set_ylabel("Кол-во врагов")
    ax1b.set_xlim(0, x_max)
    style_axes(ax1b, "Размер волны — кол-во врагов")
    fig1b.tight_layout()
    fig1b.savefig("wave_size_to30.png", dpi=120, bbox_inches="tight")
    plt.close(fig1b)
    print("Сохранено: wave_size_to30.png")

    # --- 3. Прохождение чекпоинтов (% врагов дошедших до 0..5) + средние по каждому ЧП ---
    cp_cols = ["до_0", "до_1", "до_2", "до_3", "до_4", "до_5"]
    fig2, ax2 = plt.subplots(figsize=(12, 6))
    colors_cp = plt.cm.viridis(np.linspace(0.2, 0.9, 6))
    for i, col in enumerate(cp_cols):
        vals = np.array([r[col] for r in data])
        ax2.plot(waves, vals, "o-", color=colors_cp[i], label=f"До ЧП{i} (ср. {np.mean(vals):.0f}%)", markersize=3)
    ax2.set_xlabel("Номер волны")
    ax2.set_ylabel("% врагов, дошедших до чекпоинта")
    ax2.set_ylim(-5, 105)
    ax2.set_xlim(0, x_max)
    style_axes(ax2, "Прохождение чекпоинтов по волнам")
    fig2.tight_layout()
    fig2.savefig("checkpoint_progress.png", dpi=120, bbox_inches="tight")
    plt.close(fig2)
    print("Сохранено: checkpoint_progress.png")

    # --- 4. Пройденный путь (% макс и ср.) + скользящее среднее + среднее ---
    path_max = np.array([r["путь_макс%"] for r in data])
    path_avg = np.array([r["путь_ср%"] for r in data])
    rm_path_max = rolling_mean(path_max, window)
    rm_path_avg = rolling_mean(path_avg, window)
    fig3, ax3 = plt.subplots(figsize=(12, 5))
    ax3.plot(waves, path_max, "o-", color="C0", label="Макс. прогресс по пути (%)", markersize=4)
    ax3.plot(waves, rm_path_max, "-", color="C0", linewidth=2.5, alpha=0.9, label=f"Скольз. ср. макс. (окно {window})")
    add_mean_line(ax3, path_max, "Ср. макс.%")
    ax3.plot(waves, path_avg, "s-", color="C1", label="Средний прогресс (%)", markersize=4)
    ax3.plot(waves, rm_path_avg, "-", color="C1", linewidth=2.5, alpha=0.9, label=f"Скольз. ср. ср. (окно {window})")
    ax3.set_xlabel("Номер волны")
    ax3.set_ylabel("% пути")
    ax3.set_ylim(0, 105)
    ax3.set_xlim(0, x_max)
    style_axes(ax3, "Прогресс по пути лабиринта")
    fig3.tight_layout()
    fig3.savefig("path_progress.png", dpi=120, bbox_inches="tight")
    plt.close(fig3)
    print("Сохранено: path_progress.png")

    # --- 5. Длина пути в гексах + скользящее среднее + среднее ---
    path_hexes = np.array([r.get("путь_гексов", 0) for r in data])
    rm_hexes = rolling_mean(path_hexes, window)
    fig3b, ax3b = plt.subplots(figsize=(12, 5))
    ax3b.plot(waves, path_hexes, "o-", color="C4", label="Длина пути (гексов)", markersize=4)
    ax3b.plot(waves, rm_hexes, "-", color="C4", linewidth=2.5, alpha=0.9, label=f"Скольз. ср. (окно {window})")
    add_mean_line(ax3b, path_hexes, "Ср. гексов")
    ax3b.set_xlabel("Номер волны")
    ax3b.set_ylabel("Гексов")
    ax3b.set_xlim(0, x_max)
    style_axes(ax3b, "Длина пути лабиринта в гексах")
    fig3b.tight_layout()
    fig3b.savefig("path_length_hexes.png", dpi=120, bbox_inches="tight")
    plt.close(fig3b)
    print("Сохранено: path_length_hexes.png")

    # --- 6. Время между чекпоинтами (все сегменты 0->1 … 4->5) ---
    seg_cols = ["0->1", "1->2", "2->3", "3->4", "4->5"]
    fig4, ax4 = plt.subplots(figsize=(12, 5))
    for i, col in enumerate(seg_cols):
        vals = np.array([r[col] if r[col] > 0 else np.nan for r in data])
        mean_seg = np.nanmean(vals)
        ax4.plot(waves, vals, "o-", label=f"{col} (ср. {mean_seg:.1f} с)", markersize=4)
    ax4.set_xlabel("Номер волны")
    ax4.set_ylabel("Среднее время (игр. с)")
    ax4.set_xlim(0, x_max)
    style_axes(ax4, "Время между чекпоинтами по сегментам")
    fig4.tight_layout()
    fig4.savefig("segment_times.png", dpi=120, bbox_inches="tight")
    plt.close(fig4)
    print("Сохранено: segment_times.png")

    # --- 6b. Уровень успеха по волнам (число 6+, в игре ср. 10) ---
    if data and "успех" in data[0]:
        success_vals = np.array([r.get("успех", 10) for r in data], dtype=float)
        fig_succ, ax_succ = plt.subplots(figsize=(12, 4))
        ax_succ.plot(waves, success_vals, "o-", color="C2", markersize=5, label="Уровень успеха")
        ax_succ.axhline(10, color="gray", linestyle="--", alpha=0.7, linewidth=1, label="Базовый уровень (10)")
        ax_succ.set_xlabel("Номер волны")
        ax_succ.set_ylabel("Уровень успеха")
        ax_succ.set_xlim(0, x_max)
        y_min = max(0, min(success_vals) - 1)
        ax_succ.set_ylim(y_min, max(success_vals) + 1)
        ax_succ.grid(True, alpha=0.3)
        ax_succ.legend(loc="upper right")
        ax_succ.set_title("Уровень успеха по волнам")
        fig_succ.tight_layout()
        fig_succ.savefig("wave_success.png", dpi=120, bbox_inches="tight")
        plt.close(fig_succ)
        print("Сохранено: wave_success.png")

    # --- 6c. Руда по вышкам (среднее за раунд): барчарт ---
    if tower_ore_data:
        names = [r["вышка"] for r in tower_ore_data]
        ore_total = [r["руда_всего"] for r in tower_ore_data]
        fig_tower, ax_tower = plt.subplots(figsize=(12, 6))
        x_pos = np.arange(len(names))
        bars = ax_tower.bar(x_pos, ore_total, color="C5", alpha=0.7)
        ax_tower.set_xticks(x_pos)
        ax_tower.set_xticklabels(names, rotation=45, ha="right")
        ax_tower.set_ylabel("Руда всего (ср. за раунд)")
        ax_tower.set_xlabel("Вышка")
        ax_tower.set_title("Руда по вышкам (среднее потребление за раунд)")
        ax_tower.grid(True, alpha=0.3, axis="y")
        fig_tower.tight_layout()
        fig_tower.savefig("tower_ore_per_round.png", dpi=120, bbox_inches="tight")
        plt.close(fig_tower)
        print("Сохранено: tower_ore_per_round.png")

    # --- 7. Тепловая карта: волна x чекпоинт (% дошедших) ---
    cp_cols_6 = ["до_0", "до_1", "до_2", "до_3", "до_4", "до_5"]
    fig5, ax5 = plt.subplots(figsize=(12, 6))
    cp_matrix = np.array([[r[col] for col in cp_cols_6] for r in data])
    if cp_matrix.size > 0:
        im = ax5.imshow(cp_matrix.T, aspect="auto", cmap="YlOrRd", vmin=0, vmax=100, origin="lower")
        ax5.set_yticks(range(6))
        ax5.set_yticklabels(["До 0", "До 1", "До 2", "До 3", "До 4", "До 5"])
        step = max(1, n // 18)
        ax5.set_xticks(range(0, n, step))
        ax5.set_xticklabels([int(waves[i]) for i in range(0, n, step)])
        plt.colorbar(im, ax=ax5, label="% врагов")
    ax5.set_xlabel("Номер волны")
    ax5.set_ylabel("Чекпоинт")
    ax5.set_title("Тепловая карта: % врагов, дошедших до чекпоинта")
    fig5.tight_layout()
    fig5.savefig("checkpoint_heatmap.png", dpi=120, bbox_inches="tight")
    plt.close(fig5)
    print("Сохранено: checkpoint_heatmap.png")

    # --- 8. Руда: траты за раунд, руда/сек, добыто, майнеры (4 подграфика) ---
    fig_ore, axes_ore = plt.subplots(2, 2, figsize=(13, 10))
    ore_spent = np.array([r.get("руда_трат", 0) for r in data])
    ore_sec = np.array([r.get("руда_сек", 0) for r in data])
    ore_mined = np.array([r.get("руда_доб", 0) for r in data])
    miner_hex = np.array([r.get("майнер_гексов", 0) for r in data])
    for arr, ax, ylabel, title in [
        (ore_spent, axes_ore[0, 0], "Руда (ед.)", "Руда израсходовано за раунд"),
        (ore_sec, axes_ore[0, 1], "Руда/сек", "Руда в секунду (среднее за волну)"),
        (ore_mined, axes_ore[1, 0], "Руда (ед.)", "Руда добыто за волну"),
        (miner_hex, axes_ore[1, 1], "Гексов", "Гексов занято майнерами"),
    ]:
        ax.plot(waves, arr, "o-", color="C5", markersize=4, label="По волнам")
        ax.plot(waves, rolling_mean(arr, window), "-", color="C5", linewidth=2, alpha=0.9, label=f"Скольз. ср. (окно {window})")
        m = np.nanmean(arr)
        ax.axhline(m, color="gray", linestyle="--", alpha=0.7, label=f"Ср. за всё: {m:.1f}")
        ax.set_xlabel("Номер волны")
        ax.set_ylabel(ylabel)
        ax.set_title(title)
        ax.set_xlim(0, x_max)
        ax.grid(True, alpha=0.3)
        ax.legend(loc="best", fontsize=7)
    fig_ore.suptitle("Руда по волнам", fontsize=12)
    fig_ore.tight_layout()
    fig_ore.savefig("ore_metrics.png", dpi=120, bbox_inches="tight")
    plt.close(fig_ore)
    print("Сохранено: ore_metrics.png")

    # --- 9. Руда по секторам (центр, середина, конец) ---
    ore_center = np.array([r.get("руда_центр", 0) for r in data])
    ore_middle = np.array([r.get("руда_серед", 0) for r in data])
    ore_end = np.array([r.get("руда_конец", 0) for r in data])
    fig_sec, ax_sec = plt.subplots(figsize=(12, 5))
    ax_sec.fill_between(waves, 0, ore_center, alpha=0.3, color="C0")
    ax_sec.fill_between(waves, ore_center, ore_center + ore_middle, alpha=0.3, color="C1")
    ax_sec.fill_between(waves, ore_center + ore_middle, ore_center + ore_middle + ore_end, alpha=0.3, color="C2")
    ax_sec.plot(waves, ore_center, "o-", color="C0", markersize=4, label=f"Центр (ср. {np.mean(ore_center):.0f})")
    ax_sec.plot(waves, ore_middle, "s-", color="C1", markersize=4, label=f"Середина (ср. {np.mean(ore_middle):.0f})")
    ax_sec.plot(waves, ore_end, "^-", color="C2", markersize=4, label=f"Конец (ср. {np.mean(ore_end):.0f})")
    ax_sec.set_xlabel("Номер волны")
    ax_sec.set_ylabel("Руда израсходовано по секторам")
    ax_sec.set_xlim(0, x_max)
    ax_sec.legend(loc="upper right", fontsize=8)
    ax_sec.grid(True, alpha=0.3)
    ax_sec.set_title("Траты руды по секторам карты (центр / середина / конец)")
    fig_sec.tight_layout()
    fig_sec.savefig("ore_by_sector.png", dpi=120, bbox_inches="tight")
    plt.close(fig_sec)
    print("Сохранено: ore_by_sector.png")

    # --- 10. Полный дашборд 3x4: все ключевые метрики + средние ---
    fig6, axes = plt.subplots(3, 4, figsize=(16, 12))

    ax = axes[0, 0]
    ax.plot(waves, [r["длит_игр"] for r in data], "o-", color="C0", markersize=3)
    ax.axhline(np.mean([r["длит_игр"] for r in data]), color="gray", linestyle="--", alpha=0.7, label=f"Ср. {np.mean([r['длит_игр'] for r in data]):.0f}")
    ax.set_title("Длительность (игр. с)")
    ax.set_xlabel("Волна")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=6)

    ax = axes[0, 1]
    ax.bar(waves, [r["врагов"] for r in data], color="C2", alpha=0.7)
    ax.axhline(np.mean([r["врагов"] for r in data]), color="gray", linestyle="--", alpha=0.7, label=f"Ср. {np.mean([r['врагов'] for r in data]):.1f}")
    ax.set_title("Врагов в волне")
    ax.set_xlabel("Волна")
    ax.grid(True, alpha=0.3, axis="y")
    ax.legend(fontsize=6)

    ax = axes[0, 2]
    ax.plot(waves, [r["путь_макс%"] for r in data], "o-", color="C0", markersize=3, label="Макс %")
    ax.plot(waves, [r["путь_ср%"] for r in data], "s-", color="C1", markersize=3, label="Ср %")
    ax.axhline(np.mean([r["путь_макс%"] for r in data]), color="C0", linestyle="--", alpha=0.5)
    ax.axhline(np.mean([r["путь_ср%"] for r in data]), color="C1", linestyle="--", alpha=0.5)
    ax.set_title("Прогресс пути (%)")
    ax.set_xlabel("Волна")
    ax.set_ylim(0, 105)
    ax.legend(fontsize=6)
    ax.grid(True, alpha=0.3)

    ax = axes[0, 3]
    ph = [r.get("путь_гексов", 0) for r in data]
    ax.plot(waves, ph, "o-", color="C4", markersize=3)
    ax.axhline(np.mean(ph), color="gray", linestyle="--", alpha=0.7, label=f"Ср. {np.mean(ph):.0f}")
    ax.set_title("Длина пути (гексов)")
    ax.set_xlabel("Волна")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=6)

    for i, col in enumerate(cp_cols_6[:4]):
        axes[1, 0].plot(waves, [r[col] for r in data], "o-", label=f"до {i}", markersize=2)
    axes[1, 0].axhline(np.mean([r["до_0"] for r in data]), color="gray", linestyle="--", alpha=0.5)
    axes[1, 0].set_title("Чекпоинты 0–3 (%)")
    axes[1, 0].set_xlabel("Волна")
    axes[1, 0].set_ylim(0, 105)
    axes[1, 0].legend(loc="upper right", fontsize=5)
    axes[1, 0].grid(True, alpha=0.3)

    axes[1, 1].plot(waves, [r["0->1"] for r in data], "o-", label="0->1", markersize=2)
    axes[1, 1].plot(waves, [r["1->2"] for r in data], "s-", label="1->2", markersize=2)
    axes[1, 1].plot(waves, [r["2->3"] for r in data], "^-", label="2->3", markersize=2)
    axes[1, 1].set_title("Время сегментов (игр. с)")
    axes[1, 1].set_xlabel("Волна")
    axes[1, 1].legend(fontsize=6)
    axes[1, 1].grid(True, alpha=0.3)

    ax = axes[1, 2]
    ore_spent_vals = [r.get("руда_трат", 0) for r in data]
    ax.plot(waves, ore_spent_vals, "o-", color="C5", markersize=3)
    ax.axhline(np.mean(ore_spent_vals), color="gray", linestyle="--", alpha=0.7, label=f"Ср. {np.mean(ore_spent_vals):.0f}")
    ax.set_title("Руда трат за раунд")
    ax.set_xlabel("Волна")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=6)

    ax = axes[1, 3]
    osec = [r.get("руда_сек", 0) for r in data]
    ax.plot(waves, osec, "o-", color="C5", markersize=3)
    ax.axhline(np.mean(osec), color="gray", linestyle="--", alpha=0.7, label=f"Ср. {np.mean(osec):.2f}")
    ax.set_title("Руда/сек")
    ax.set_xlabel("Волна")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=6)

    ax = axes[2, 0]
    om = [r.get("руда_доб", 0) for r in data]
    ax.plot(waves, om, "o-", color="C5", markersize=3)
    ax.axhline(np.mean(om), color="gray", linestyle="--", alpha=0.7, label=f"Ср. {np.mean(om):.0f}")
    ax.set_title("Руда добыто за волну")
    ax.set_xlabel("Волна")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=6)

    ax = axes[2, 1]
    mh = [r.get("майнер_гексов", 0) for r in data]
    ax.plot(waves, mh, "o-", color="C6", markersize=3)
    ax.axhline(np.mean(mh), color="gray", linestyle="--", alpha=0.7, label=f"Ср. {np.mean(mh):.1f}")
    ax.set_title("Майнеров (гексов)")
    ax.set_xlabel("Волна")
    ax.grid(True, alpha=0.3)
    ax.legend(fontsize=6)

    axes[2, 2].plot(waves, ore_center, "o-", color="C0", markersize=2, label="Центр")
    axes[2, 2].plot(waves, ore_middle, "s-", color="C1", markersize=2, label="Середина")
    axes[2, 2].plot(waves, ore_end, "^-", color="C2", markersize=2, label="Конец")
    axes[2, 2].set_title("Руда по секторам")
    axes[2, 2].set_xlabel("Волна")
    axes[2, 2].legend(fontsize=6)
    axes[2, 2].grid(True, alpha=0.3)

    axes[2, 3].axis("off")
    summary_text = (
        f"Волн: {n} (1–{max(waves) if waves else 0})\n"
        f"Ср. длит. игр: {np.mean(dur_igr):.1f} с\n"
        f"Ср. длит. реал: {np.mean(dur_real):.1f} с\n"
        f"Ср. врагов: {np.mean(enemies):.1f}\n"
        f"Ср. путь макс%: {np.mean(path_max):.0f}%\n"
        f"Ср. путь ср%: {np.mean(path_avg):.0f}%\n"
        f"Ср. руда трат: {np.mean(ore_spent):.0f}\n"
        f"Ср. руда/сек: {np.mean(ore_sec):.2f}\n"
        f"Ср. руда добыто: {np.mean(ore_mined):.0f}\n"
        f"Ср. майнеров: {np.mean(miner_hex):.1f}"
    )
    if data and "hp_игрока" in data[0]:
        last = data[-1]
        summary_text += (
            f"\n--- На конец прогона ---\n"
            f"HP: {last.get('hp_игрока', 0)}\n"
            f"Ур: {last.get('lvl_игрока', 1)}\n"
            f"XP всего: {last.get('xp_всего', 0)}\n"
            f"Пропущено врагов: {last.get('пропущено_врагов', 0)}\n"
            f"Руда всего: {last.get('руда_всего', 0):.0f}\n"
            f"Уровень успеха: {last.get('успех', 10):.0f}"
        )
    axes[2, 3].text(0.1, 0.5, summary_text, transform=axes[2, 3].transAxes, fontsize=9, verticalalignment="center", family="monospace")

    fig6.suptitle("Полная сводка по волнам (все метрики + средние)", fontsize=13)
    fig6.tight_layout()
    fig6.savefig("wave_dashboard.png", dpi=120, bbox_inches="tight")
    plt.close(fig6)
    print("Сохранено: wave_dashboard.png")

    print("\nГотово. Все графики в текущей директории.")


if __name__ == "__main__":
    main()
