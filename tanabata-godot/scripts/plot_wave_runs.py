#!/usr/bin/env python3
"""
Comprehensive balance analytics for Tanabata tower defense.
Reads wave_*.csv from headless runs and produces ~15 analytical charts + console report.
Usage: python plot_wave_runs.py [folder_with_csvs]
"""
import sys, os, glob, csv
from collections import defaultdict
import numpy as np
import matplotlib
matplotlib.use("Agg")
import matplotlib.pyplot as plt
from matplotlib.gridspec import GridSpec

SCRIPT_DIR = os.path.dirname(os.path.abspath(__file__))
DEFAULT_DIR = os.path.join(SCRIPT_DIR, "..", "snapshots")

ENEMY_NAMES = {
    "ENEMY_NORMAL_WEAK": "Слабый 1", "ENEMY_NORMAL_WEAK_2": "Слабый 2",
    "ENEMY_NORMAL": "Обычный 1", "ENEMY_NORMAL_2": "Обычный 2",
    "ENEMY_TOUGH": "Крепкий 1", "ENEMY_TOUGH_2": "Крепкий 2",
    "ENEMY_MAGIC_RESIST": "Маг.щит 1", "ENEMY_MAGIC_RESIST_2": "Маг.щит 2",
    "ENEMY_PHYSICAL_RESIST": "Физ.щит 1", "ENEMY_PHYSICAL_RESIST_2": "Физ.щит 2",
    "ENEMY_FAST": "Быстрый 1", "ENEMY_FAST_2": "Быстрый 2",
    "ENEMY_BOSS": "Босс", "ENEMY_FLYING": "Летающий",
    "ENEMY_FLYING_WEAK": "Летающий сл.", "ENEMY_FLYING_TOUGH": "Летающий кр.",
    "ENEMY_FLYING_FAST": "Летающий быстр.", "ENEMY_HEALER": "Хиллер",
    "ENEMY_TANK": "Танк", "ENEMY_DARKNESS_1": "Тьма 1", "ENEMY_DARKNESS_2": "Тьма 2",
}

def en(d): return ENEMY_NAMES.get(d, d.replace("ENEMY_","").replace("_"," ").title())
def si(v, d=0):
    try: return int(v)
    except: return d
def sf(v, d=0.0):
    try: return float(v)
    except: return d
def rm(a, w=5):
    n=len(a); o=np.full(n,np.nan)
    for i in range(n):
        lo=max(0,i-w//2); hi=min(n,i+w//2+1); o[i]=np.nanmean(a[lo:hi])
    return o

def load(d):
    flat=[]
    for p in sorted(glob.glob(os.path.join(d,"wave_*.csv")),
                    key=lambda p: si(os.path.basename(p).replace("wave_","").replace(".csv",""))):
        with open(p,"r",encoding="utf-8") as f:
            for r in csv.DictReader(f):
                for k in ["run_index","seed","wave_number","spawned","killed","passed",
                           "total_hp","success","game_over","success_lvl_before",
                           "success_lvl_after","player_hp_before","player_hp_after",
                           "enemy_base_speed","enemy_base_hp","enemy_flying","source_wave"]:
                    r[k]=si(r.get(k,0))
                for k in ["duration_sec","ore_spent","enemy_regen_base"]:
                    r[k]=sf(r.get(k,0))
                ab=str(r.get("enemy_abilities","") or "")
                r["enemy_abilities"]=ab.replace(",",";")
                r["snapshot_id"]=str(r.get("snapshot_id","") or "all")
                r["hp_lost"]=r["player_hp_before"]-r["player_hp_after"]
                r["success_delta"]=r["success_lvl_after"]-r["success_lvl_before"]
                r["kill_rate"]=r["killed"]/max(1,r["spawned"])
                r["hp_per_enemy"]=r["total_hp"]/max(1,r["spawned"])
                flat.append(r)
    return flat

def savefig(fig,d,name):
    fig.savefig(os.path.join(d,name),dpi=120,bbox_inches="tight"); plt.close(fig); print("  "+name)

def main():
    d=sys.argv[1] if len(sys.argv)>1 else DEFAULT_DIR
    if not os.path.isdir(d): print("Not found:",d); sys.exit(1)
    flat=load(d)
    if not flat: print("No CSVs in",d); sys.exit(1)

    W=sorted(set(r["wave_number"] for r in flat))
    E=sorted(set(r["enemy_def_id"] for r in flat))
    out=d; plt.rcParams.update({"figure.figsize":(14,8),"font.size":9})
    print("Data: %d waves, %d runs, %d enemy types" % (len(W),len(flat),len(E)))
    print("\nPlots:")

    # --- aggregations ---
    es={}
    for eid in E:
        rows=[r for r in flat if r["enemy_def_id"]==eid]; n=len(rows)
        es[eid]=dict(n=n,
            fail_pct=100*sum(1-r["success"] for r in rows)/n,
            kill_pct=100*sum(r["killed"] for r in rows)/max(1,sum(r["spawned"] for r in rows)),
            m_passed=np.mean([r["passed"] for r in rows]),
            m_hp_lost=np.mean([r["hp_lost"] for r in rows]),
            m_suc_d=np.mean([r["success_delta"] for r in rows]),
            m_ore=np.mean([r["ore_spent"] for r in rows]),
            m_dur=np.mean([r["duration_sec"] for r in rows]),
            m_total_hp=np.mean([r["total_hp"] for r in rows]),
            m_hp_per_e=np.mean([r["hp_per_enemy"] for r in rows]),
            base_hp=rows[0]["enemy_base_hp"], base_spd=rows[0]["enemy_base_speed"],
            regen=rows[0]["enemy_regen_base"], flying=rows[0]["enemy_flying"],
            abilities=rows[0]["enemy_abilities"])
    wa={}
    for wn in W:
        rows=[r for r in flat if r["wave_number"]==wn]; n=len(rows)
        wa[wn]=dict(n=n,
            suc_pct=100*sum(r["success"] for r in rows)/n,
            m_passed=np.mean([r["passed"] for r in rows]),
            m_hp_lost=np.mean([r["hp_lost"] for r in rows]),
            m_suc_d=np.mean([r["success_delta"] for r in rows]),
            m_ore=np.mean([r["ore_spent"] for r in rows]),
            m_dur=np.mean([r["duration_sec"] for r in rows]),
            m_total_hp=np.mean([r["total_hp"] for r in rows]),
            m_regen=np.mean([r["enemy_regen_base"] for r in rows]),
            enemies=sorted(set(r["enemy_def_id"] for r in rows)))
    ab_set=set()
    for r in flat:
        for a in r["enemy_abilities"].split(";"):
            a=a.strip()
            if a: ab_set.add(a)
    ab_s={}
    for ab in sorted(ab_set):
        rw=[r for r in flat if ab in r["enemy_abilities"]]
        rn=[r for r in flat if ab not in r["enemy_abilities"] and r["enemy_abilities"]!=""]
        if not rw: continue
        ab_s[ab]=dict(n=len(rw),
            fail_pct=100*sum(1-r["success"] for r in rw)/len(rw),
            m_hp_lost=np.mean([r["hp_lost"] for r in rw]),
            m_suc_d=np.mean([r["success_delta"] for r in rw]),
            m_ore=np.mean([r["ore_spent"] for r in rw]),
            no_ab_fail=100*sum(1-r["success"] for r in rn)/max(1,len(rn)))

    # power score
    pw={}
    for eid in E:
        s=es[eid]
        pw[eid]=(s["fail_pct"]*0.35+(100-s["kill_pct"])*0.20+min(s["m_hp_lost"],100)*0.20+min(abs(s["m_suc_d"])*10,100)*0.15+min(s["m_passed"]*5,100)*0.10)
    srt=sorted(E,key=lambda e:pw[e],reverse=True)

    # wave arrays
    suc_a=np.array([wa[w]["suc_pct"] for w in W])
    hp_a=np.array([wa[w]["m_hp_lost"] for w in W])
    ore_a=np.array([wa[w]["m_ore"] for w in W])
    sd_a=np.array([wa[w]["m_suc_d"] for w in W])
    dur_a=np.array([wa[w]["m_dur"] for w in W])
    thp_a=np.array([wa[w]["m_total_hp"] for w in W])
    reg_a=np.array([wa[w]["m_regen"] for w in W])
    diff_a=100-suc_a  # difficulty = 100 - success%

    # ====================================================================
    # 1. ENEMY POWER RANKING (with stats)
    # ====================================================================
    fig,ax=plt.subplots(figsize=(14,max(5,len(srt)*0.55)))
    y=np.arange(len(srt)); pv=[pw[e] for e in srt]
    colors=plt.cm.RdYlGn_r(np.array(pv)/max(max(pv),1))
    ax.barh(y,pv,color=colors,edgecolor="gray",linewidth=0.5)
    ax.set_yticks(y)
    ax.set_yticklabels(["%s  HP:%d spd:%d reg:%.1f %s%s"%(en(e),es[e]["base_hp"],es[e]["base_spd"],es[e]["regen"],"[fly] " if es[e]["flying"] else "","[%s]"%es[e]["abilities"] if es[e]["abilities"] else "") for e in srt])
    for i,v in enumerate(pv): ax.text(v+0.5,i,"%.0f"%v,va="center",fontsize=7)
    ax.set_xlabel("Сила (композит)")
    ax.set_title("Рейтинг силы врагов = 35%% провал + 20%% (100-kill%%) + 20%% HP урон + 15%% |suc delta|*10 + 10%% passed*5")
    ax.grid(True,alpha=0.3,axis="x"); ax.invert_yaxis(); fig.tight_layout()
    savefig(fig,out,"01_enemy_power_ranking.png")

    # ====================================================================
    # 2. PACING CURVE: difficulty over waves + ideal curve
    # ====================================================================
    fig,ax=plt.subplots(figsize=(16,6))
    ax.bar(W,diff_a,color=["#e74c3c" if d>60 else "#f39c12" if d>30 else "#2ecc71" for d in diff_a],alpha=0.7,label="Факт. сложность")
    ax.plot(W,rm(diff_a,7),"o-",color="darkred",linewidth=2.5,markersize=3,label="Скольз. ср. (7)")
    ideal=np.interp(W,[min(W),max(W)*0.15,max(W)*0.3,max(W)*0.5,max(W)*0.7,max(W)*0.85,max(W)],[20,30,45,55,65,75,85])
    ax.plot(W,ideal,"--",color="blue",linewidth=2,alpha=0.7,label="Идеальная кривая пейсинга")
    for lo,hi in [(6,9),(11,15),(16,19),(21,29),(31,39)]:
        vl=max(min(W),lo)-0.5; vh=min(max(W),hi)+0.5
        if vl<vh: ax.axvspan(vl,vh,alpha=0.08,color="purple")
    ax.set_xlabel("Волна"); ax.set_ylabel("Сложность (100 - %% успеха)")
    ax.set_title("Кривая пейсинга: факт vs идеал (синяя = плавный рост, серые = шаффл-зоны)")
    ax.set_xticks(W); ax.legend(fontsize=8); ax.grid(True,alpha=0.3); ax.set_ylim(-5,105)
    fig.tight_layout(); savefig(fig,out,"02_pacing_curve.png")

    # ====================================================================
    # 3. CORRELATIONS: enemy stats vs outcomes (2x3 scatter)
    # ====================================================================
    fig,axes=plt.subplots(2,3,figsize=(18,10))
    for eid in E:
        s=es[eid]; sz=max(20,s["n"]/2)
        data=[(s["m_total_hp"],s["fail_pct"]),(s["base_spd"],s["fail_pct"]),(s["regen"],s["fail_pct"]),
              (s["m_total_hp"],s["m_hp_lost"]),(s["base_spd"],s["m_hp_lost"]),(s["regen"],s["m_hp_lost"])]
        for ai,(xv,yv) in enumerate(data):
            axes.flat[ai].scatter(xv,yv,s=sz,alpha=0.7,zorder=5)
            axes.flat[ai].annotate(en(eid),(xv,yv),textcoords="offset points",xytext=(3,3),fontsize=5)
    titles=[("Ср. HP волны","% провалов"),("Base Speed","% провалов"),("Regen/sec","% провалов"),
            ("Ср. HP волны","Ср. потеря HP"),("Base Speed","Ср. потеря HP"),("Regen/sec","Ср. потеря HP")]
    for ai,(xl,yl) in enumerate(titles):
        axes.flat[ai].set_xlabel(xl); axes.flat[ai].set_ylabel(yl)
        axes.flat[ai].set_title("%s vs %s"%(xl,yl)); axes.flat[ai].grid(True,alpha=0.3)
    fig.suptitle("Корреляции: характеристики врагов vs результат",fontsize=13)
    fig.tight_layout(); savefig(fig,out,"03_enemy_stat_correlations.png")

    # ====================================================================
    # 4. WAVE REGEN vs HP LOST + SUCCESS DELTA
    # ====================================================================
    fig,axes=plt.subplots(1,3,figsize=(18,5))
    ax=axes[0]
    ax.bar(W,reg_a,color="C4",alpha=0.7,label="Ср. реген/сек")
    ax.plot(W,rm(reg_a,5),"o-",color="purple",linewidth=2,markersize=3); ax.set_xlabel("Волна")
    ax.set_ylabel("Реген/сек"); ax.set_title("Реген врагов по волнам"); ax.set_xticks(W); ax.grid(True,alpha=0.3)
    ax=axes[1]
    for wn in W: ax.scatter(wa[wn]["m_regen"],wa[wn]["m_hp_lost"],s=80,alpha=0.7,zorder=5); ax.annotate(str(wn),(wa[wn]["m_regen"],wa[wn]["m_hp_lost"]),fontsize=6)
    ax.set_xlabel("Ср. реген врагов"); ax.set_ylabel("Ср. потеря HP игрока")
    ax.set_title("Реген vs HP потери (по волнам)"); ax.grid(True,alpha=0.3)
    ax=axes[2]
    for wn in W: ax.scatter(wa[wn]["m_regen"],wa[wn]["m_suc_d"],s=80,alpha=0.7,zorder=5); ax.annotate(str(wn),(wa[wn]["m_regen"],wa[wn]["m_suc_d"]),fontsize=6)
    ax.set_xlabel("Ср. реген врагов"); ax.set_ylabel("Дельта успеха"); ax.axhline(0,color="black",lw=0.8)
    ax.set_title("Реген vs дельта успеха"); ax.grid(True,alpha=0.3)
    fig.suptitle("Влияние регена врагов на игру",fontsize=13)
    fig.tight_layout(); savefig(fig,out,"04_regen_impact.png")

    # ====================================================================
    # 5. TOTAL HP vs OUTCOMES (per wave scatter)
    # ====================================================================
    fig,axes=plt.subplots(1,3,figsize=(18,5))
    for wn in W:
        axes[0].scatter(wa[wn]["m_total_hp"],100-wa[wn]["suc_pct"],s=60,alpha=0.7); axes[0].annotate(str(wn),(wa[wn]["m_total_hp"],100-wa[wn]["suc_pct"]),fontsize=6)
        axes[1].scatter(wa[wn]["m_total_hp"],wa[wn]["m_hp_lost"],s=60,alpha=0.7); axes[1].annotate(str(wn),(wa[wn]["m_total_hp"],wa[wn]["m_hp_lost"]),fontsize=6)
        axes[2].scatter(wa[wn]["m_total_hp"],wa[wn]["m_ore"],s=60,alpha=0.7); axes[2].annotate(str(wn),(wa[wn]["m_total_hp"],wa[wn]["m_ore"]),fontsize=6)
    for ax,yl,t in [(axes[0],"Сложность (%)","HP волны vs Сложность"),(axes[1],"HP потери","HP волны vs HP потери"),(axes[2],"Руда","HP волны vs Руда")]:
        ax.set_xlabel("Ср. суммарное HP волны"); ax.set_ylabel(yl); ax.set_title(t); ax.grid(True,alpha=0.3)
    fig.suptitle("Суммарное HP волны: влияние на сложность, HP и руду",fontsize=13)
    fig.tight_layout(); savefig(fig,out,"05_wave_hp_impact.png")

    # ====================================================================
    # 6. WAVE METRICS 4-panel (success, HP lost, ore, success delta)
    # ====================================================================
    fig,axes=plt.subplots(2,2,figsize=(16,10))
    ax=axes[0,0]; ax.bar(W,suc_a,color=["#2ecc71" if s>50 else "#e74c3c" for s in suc_a],alpha=0.8)
    ax.axhline(np.mean(suc_a),color="gray",ls="--",alpha=0.7,label="Ср. %.0f%%"%np.mean(suc_a))
    ax.set_title("Успех (%)"); ax.set_xticks(W); ax.set_ylim(0,105); ax.grid(True,alpha=0.3); ax.legend(fontsize=7)
    ax=axes[0,1]; ax.bar(W,hp_a,color="C3",alpha=0.7); ax.plot(W,rm(hp_a),"o-",color="darkred",lw=2,ms=3)
    ax.axhline(np.mean(hp_a),color="gray",ls="--",alpha=0.7,label="Ср. %.1f"%np.mean(hp_a))
    ax.set_title("Ср. потеря HP"); ax.set_xticks(W); ax.grid(True,alpha=0.3); ax.legend(fontsize=7)
    ax=axes[1,0]; ax.bar(W,ore_a,color="C5",alpha=0.7); ax.plot(W,rm(ore_a),"o-",color="C5",lw=2,ms=3)
    ax.axhline(np.mean(ore_a),color="gray",ls="--",alpha=0.7,label="Ср. %.1f"%np.mean(ore_a))
    ax.set_title("Ср. руда"); ax.set_xticks(W); ax.grid(True,alpha=0.3); ax.legend(fontsize=7)
    ax=axes[1,1]; ax.bar(W,sd_a,color=["#e74c3c" if d<0 else "#2ecc71" for d in sd_a],alpha=0.8); ax.axhline(0,color="black",lw=0.8)
    ax.axhline(np.mean(sd_a),color="gray",ls="--",alpha=0.7,label="Ср. %.2f"%np.mean(sd_a))
    ax.set_title("Дельта успеха"); ax.set_xticks(W); ax.grid(True,alpha=0.3); ax.legend(fontsize=7)
    fig.suptitle("Метрики по волнам",fontsize=13); fig.tight_layout(); savefig(fig,out,"06_wave_metrics.png")

    # ====================================================================
    # 7. ABILITY IMPACT (3-panel)
    # ====================================================================
    if ab_s:
        abs_s=sorted(ab_s.keys(),key=lambda a:ab_s[a]["fail_pct"],reverse=True)
        fig,axes=plt.subplots(1,3,figsize=(18,max(4,len(abs_s)*0.5)))
        y=np.arange(len(abs_s))
        ax=axes[0]; ax.barh(y,[ab_s[a]["fail_pct"] for a in abs_s],color="C3",alpha=0.7)
        ax.set_yticks(y); ax.set_yticklabels(["%s (%d)"%(a,ab_s[a]["n"]) for a in abs_s])
        for i,a in enumerate(abs_s): ax.text(ab_s[a]["fail_pct"]+0.5,i,"%.0f%%"%ab_s[a]["fail_pct"],va="center",fontsize=7)
        ax.set_xlabel("% провалов"); ax.set_title("Провалы"); ax.grid(True,alpha=0.3,axis="x"); ax.invert_yaxis()
        ax=axes[1]; ax.barh(y,[ab_s[a]["m_hp_lost"] for a in abs_s],color="C1",alpha=0.7)
        ax.set_yticks(y); ax.set_yticklabels(abs_s)
        for i,a in enumerate(abs_s): ax.text(ab_s[a]["m_hp_lost"]+0.3,i,"%.1f"%ab_s[a]["m_hp_lost"],va="center",fontsize=7)
        ax.set_xlabel("HP потери"); ax.set_title("HP потери"); ax.grid(True,alpha=0.3,axis="x"); ax.invert_yaxis()
        ax=axes[2]; vals=[ab_s[a]["m_suc_d"] for a in abs_s]
        ax.barh(y,vals,color=["#e74c3c" if v<0 else "#2ecc71" for v in vals])
        ax.set_yticks(y); ax.set_yticklabels(abs_s); ax.axvline(0,color="black",lw=0.8)
        for i,v in enumerate(vals): ax.text(v+(0.02 if v>=0 else -0.02),i,"%+.2f"%v,va="center",fontsize=7,ha="left" if v>=0 else "right")
        ax.set_xlabel("Дельта успеха"); ax.set_title("Влияние на успех"); ax.grid(True,alpha=0.3,axis="x"); ax.invert_yaxis()
        fig.suptitle("Влияние способностей врагов",fontsize=13); fig.tight_layout(); savefig(fig,out,"07_ability_impact.png")

    # ====================================================================
    # 8. HEATMAP: wave x enemy -> success%
    # ====================================================================
    we={}
    for r in flat:
        k=(r["wave_number"],r["enemy_def_id"]); we.setdefault(k,[]).append(r["success"])
    mx=np.full((len(W),len(E)),np.nan); cm=np.zeros((len(W),len(E)))
    for wi,wn in enumerate(W):
        for ei,eid in enumerate(E):
            k=(wn,eid)
            if k in we: mx[wi,ei]=100*np.mean(we[k]); cm[wi,ei]=len(we[k])
    fig,ax=plt.subplots(figsize=(max(10,len(E)*1.1),max(6,len(W)*0.4)))
    im=ax.imshow(mx,aspect="auto",cmap="RdYlGn",vmin=0,vmax=100,origin="lower",interpolation="nearest")
    ax.set_xticks(range(len(E))); ax.set_xticklabels([en(e) for e in E],rotation=45,ha="right")
    ax.set_yticks(range(len(W))); ax.set_yticklabels([str(w) for w in W])
    for wi in range(len(W)):
        for ei in range(len(E)):
            c=int(cm[wi,ei])
            if c>0:
                v=mx[wi,ei]; ax.text(ei,wi,"%d%%\n(%d)"%(v,c),ha="center",va="center",fontsize=4,color="black" if 30<v<70 else "white")
    plt.colorbar(im,ax=ax,label="% успеха"); ax.set_ylabel("Волна"); ax.set_title("Тепловая карта: волна x враг -> % успеха")
    fig.tight_layout(); savefig(fig,out,"08_wave_enemy_heatmap.png")

    # ====================================================================
    # 9. STACKED FAILURES by enemy per wave
    # ====================================================================
    fig,ax=plt.subplots(figsize=(16,6))
    cmap=plt.cm.tab20; ecol={eid:cmap(i/max(1,len(E)-1)) for i,eid in enumerate(E)}
    bot=np.zeros(len(W))
    for eid in E:
        fa=np.array([sum(1 for s in we.get((wn,eid),[]) if s==0) for wn in W])
        if np.sum(fa)>0:
            ax.bar(W,fa,bottom=bot,color=ecol[eid],label=en(eid),edgecolor="white",linewidth=0.3); bot+=fa
    ax.set_xlabel("Волна"); ax.set_ylabel("Провалов"); ax.set_title("Провалы: какой враг виноват")
    ax.legend(fontsize=6,ncol=3,loc="upper left"); ax.grid(True,alpha=0.3,axis="y"); ax.set_xticks(W)
    fig.tight_layout(); savefig(fig,out,"09_failures_by_enemy.png")

    # ====================================================================
    # 10. ORE vs DURATION scatter + per-enemy ore
    # ====================================================================
    fig,axes=plt.subplots(1,2,figsize=(14,6))
    ax=axes[0]
    for wn in W: ax.scatter(wa[wn]["m_dur"],wa[wn]["m_ore"],s=60,alpha=0.7); ax.annotate(str(wn),(wa[wn]["m_dur"],wa[wn]["m_ore"]),fontsize=6)
    ax.set_xlabel("Ср. длительность (с)"); ax.set_ylabel("Ср. руда"); ax.set_title("Длительность vs Руда (по волнам)"); ax.grid(True,alpha=0.3)
    ax=axes[1]
    srt_ore=sorted(E,key=lambda e:es[e]["m_ore"],reverse=True)
    y2=np.arange(len(srt_ore)); ax.barh(y2,[es[e]["m_ore"] for e in srt_ore],color="C5",alpha=0.7)
    ax.set_yticks(y2); ax.set_yticklabels(["%s (%.0fс)"%(en(e),es[e]["m_dur"]) for e in srt_ore])
    for i,e in enumerate(srt_ore): ax.text(es[e]["m_ore"]+0.3,i,"%.1f"%es[e]["m_ore"],va="center",fontsize=7)
    ax.set_xlabel("Ср. руда"); ax.set_title("Руда по типу врага"); ax.grid(True,alpha=0.3,axis="x"); ax.invert_yaxis()
    fig.suptitle("Расход руды",fontsize=13); fig.tight_layout(); savefig(fig,out,"10_ore_analysis.png")

    # ====================================================================
    # 11. ENEMY SUCCESS IMPACT (delta bar)
    # ====================================================================
    fig,ax=plt.subplots(figsize=(13,max(5,len(srt)*0.5)))
    y=np.arange(len(srt)); ds=[es[e]["m_suc_d"] for e in srt]
    ax.barh(y,ds,color=["#e74c3c" if d<0 else "#2ecc71" for d in ds],edgecolor="gray",lw=0.5)
    ax.set_yticks(y); ax.set_yticklabels(["%s (%d)"%(en(e),es[e]["n"]) for e in srt])
    for i,v in enumerate(ds): ax.text(v+(0.03 if v>=0 else -0.03),i,"%+.2f"%v,va="center",fontsize=7,ha="left" if v>=0 else "right")
    ax.axvline(0,color="black",lw=0.8); ax.set_xlabel("Дельта успеха"); ax.set_title("Влияние врагов на уровень успеха")
    ax.grid(True,alpha=0.3,axis="x"); ax.invert_yaxis(); fig.tight_layout(); savefig(fig,out,"11_enemy_success_delta.png")

    # ====================================================================
    # 12. ENEMY HP IMPACT (bar)
    # ====================================================================
    fig,ax=plt.subplots(figsize=(13,max(5,len(srt)*0.5)))
    y=np.arange(len(srt)); hpl=[es[e]["m_hp_lost"] for e in srt]
    ax.barh(y,hpl,color=plt.cm.Reds(np.array(hpl)/max(max(hpl),1)),edgecolor="gray",lw=0.5)
    ax.set_yticks(y); ax.set_yticklabels([en(e) for e in srt])
    for i,v in enumerate(hpl): ax.text(v+0.3,i,"%.1f"%v,va="center",fontsize=7)
    ax.set_xlabel("Ср. HP потери"); ax.set_title("Влияние врагов на HP игрока"); ax.grid(True,alpha=0.3,axis="x")
    ax.invert_yaxis(); fig.tight_layout(); savefig(fig,out,"12_enemy_hp_impact.png")

    # ====================================================================
    # 13. BALANCE FORMULA: multiple regression attempt
    # ====================================================================
    X=[]; Y_fail=[]; Y_hp=[]; labels=[]
    for eid in E:
        s=es[eid]
        X.append([s["m_total_hp"],s["base_spd"],s["regen"],s["flying"],1 if s["abilities"] else 0])
        Y_fail.append(s["fail_pct"]); Y_hp.append(s["m_hp_lost"]); labels.append(en(eid))
    X=np.array(X); Y_fail=np.array(Y_fail); Y_hp=np.array(Y_hp)
    names_x=["TotalHP","Speed","Regen","Flying","HasAbility"]
    try:
        coeffs_f=np.linalg.lstsq(X,Y_fail,rcond=None)[0]
        pred_f=X@coeffs_f; resid_f=Y_fail-pred_f
        coeffs_h=np.linalg.lstsq(X,Y_hp,rcond=None)[0]
        pred_h=X@coeffs_h; resid_h=Y_hp-pred_h
        fig,axes=plt.subplots(2,2,figsize=(14,10))
        ax=axes[0,0]; ax.scatter(pred_f,Y_fail,s=60,alpha=0.7)
        for i,l in enumerate(labels): ax.annotate(l,(pred_f[i],Y_fail[i]),fontsize=6)
        lims=[min(min(pred_f),min(Y_fail))-5,max(max(pred_f),max(Y_fail))+5]
        ax.plot(lims,lims,"--",color="gray"); ax.set_xlabel("Предсказано"); ax.set_ylabel("Факт")
        ax.set_title("Регрессия: % провалов"); ax.grid(True,alpha=0.3)
        ax=axes[0,1]; ax.scatter(pred_h,Y_hp,s=60,alpha=0.7)
        for i,l in enumerate(labels): ax.annotate(l,(pred_h[i],Y_hp[i]),fontsize=6)
        lims2=[min(min(pred_h),min(Y_hp))-2,max(max(pred_h),max(Y_hp))+2]
        ax.plot(lims2,lims2,"--",color="gray"); ax.set_xlabel("Предсказано"); ax.set_ylabel("Факт")
        ax.set_title("Регрессия: HP потери"); ax.grid(True,alpha=0.3)
        ax=axes[1,0]; y3=np.arange(len(names_x)); ax.barh(y3,coeffs_f,color="C0",alpha=0.7)
        ax.set_yticks(y3); ax.set_yticklabels(names_x); ax.set_title("Коэффициенты: % провалов")
        ax.axvline(0,color="black",lw=0.8); ax.grid(True,alpha=0.3,axis="x")
        ax=axes[1,1]; ax.barh(y3,coeffs_h,color="C1",alpha=0.7)
        ax.set_yticks(y3); ax.set_yticklabels(names_x); ax.set_title("Коэффициенты: HP потери")
        ax.axvline(0,color="black",lw=0.8); ax.grid(True,alpha=0.3,axis="x")
        txt="Формула сложности:\n"
        txt+="  Провал%% = "+" + ".join(["%.4f*%s"%(c,n) for c,n in zip(coeffs_f,names_x)])+"\n"
        txt+="  HP_lost = "+" + ".join(["%.4f*%s"%(c,n) for c,n in zip(coeffs_h,names_x)])
        fig.suptitle("Линейная регрессия: предсказание сложности по характеристикам врага",fontsize=12)
        fig.text(0.5,0.01,txt,ha="center",fontsize=7,family="monospace",bbox=dict(boxstyle="round",facecolor="#f0f0f0",alpha=0.8))
        fig.tight_layout(rect=[0,0.06,1,0.95]); savefig(fig,out,"13_balance_regression.png")
    except Exception as ex:
        print("  [skip regression: %s]"%ex)

    # ====================================================================
    # 14. DASHBOARD
    # ====================================================================
    fig=plt.figure(figsize=(20,12)); gs=GridSpec(2,3,figure=fig)
    ax=fig.add_subplot(gs[0,0])
    top_n=min(12,len(srt)); tp=srt[:top_n]; y4=np.arange(top_n)
    ax.barh(y4,[pw[e] for e in tp],color=plt.cm.Reds(np.linspace(0.3,0.9,top_n)))
    ax.set_yticks(y4); ax.set_yticklabels([en(e) for e in tp]); ax.set_xlabel("Сила")
    ax.set_title("Топ врагов по силе"); ax.grid(True,alpha=0.3,axis="x"); ax.invert_yaxis()
    ax=fig.add_subplot(gs[0,1])
    ax.bar(W,suc_a,color=["#2ecc71" if s>50 else "#e74c3c" for s in suc_a],alpha=0.8)
    ax.axhline(np.mean(suc_a),color="gray",ls="--",alpha=0.7,label="Ср. %.0f%%"%np.mean(suc_a))
    ax.set_title("Успех (%%)"); ax.set_xticks(W[::2]); ax.set_ylim(0,105); ax.grid(True,alpha=0.3,axis="y"); ax.legend(fontsize=6)
    ax=fig.add_subplot(gs[0,2])
    ax.plot(W,diff_a,"o-",color="C3",ms=3); ax.plot(W,rm(diff_a,7),"-",color="darkred",lw=2.5)
    ax.plot(W,ideal,"--",color="blue",lw=2,alpha=0.6,label="Идеал")
    ax.set_title("Пейсинг"); ax.set_xticks(W[::2]); ax.legend(fontsize=6); ax.grid(True,alpha=0.3)
    ax=fig.add_subplot(gs[1,0])
    ax.bar(W,hp_a,color="C3",alpha=0.7); ax.axhline(np.mean(hp_a),color="gray",ls="--",alpha=0.7)
    ax.set_title("HP потери"); ax.set_xticks(W[::2]); ax.grid(True,alpha=0.3)
    ax=fig.add_subplot(gs[1,1])
    ax.bar(W,ore_a,color="C5",alpha=0.7); ax.axhline(np.mean(ore_a),color="gray",ls="--",alpha=0.7)
    ax.set_title("Руда"); ax.set_xticks(W[::2]); ax.grid(True,alpha=0.3)
    ax=fig.add_subplot(gs[1,2]); ax.axis("off")
    hardest=max(W,key=lambda w:100-wa[w]["suc_pct"]); easiest=min(W,key=lambda w:100-wa[w]["suc_pct"])
    txt=("--- СВОДКА ---\nВолн: %d | Прогонов: %d | Врагов: %d\n\n"
         "Ср. успех: %.1f%% | Ср. HP-: %.1f | Ср. руда: %.1f\nСр. дельта успеха: %+.2f\n\n"
         "Тяжелейшая: волна %d (%.0f%% усп.)\nЛегчайшая: волна %d (%.0f%% усп.)\n\n"
         "Сильнейший враг: %s (%.0f)\nСлабейший: %s (%.0f)\n\n"
         "Способности (топ-5):\n")%(
        len(W),len(flat),len(E),np.mean(suc_a),np.mean(hp_a),np.mean(ore_a),np.mean(sd_a),
        hardest,wa[hardest]["suc_pct"],easiest,wa[easiest]["suc_pct"],
        en(srt[0]),pw[srt[0]],en(srt[-1]),pw[srt[-1]])
    for ab in sorted(ab_s.keys(),key=lambda a:ab_s[a]["fail_pct"],reverse=True)[:5]:
        txt+="  %s: %.0f%% fail, HP-%.1f, suc%+.2f\n"%(ab,ab_s[ab]["fail_pct"],ab_s[ab]["m_hp_lost"],ab_s[ab]["m_suc_d"])
    ax.text(0.02,0.98,txt,transform=ax.transAxes,fontsize=9,va="top",family="monospace",bbox=dict(boxstyle="round",facecolor="#f0f0f0",alpha=0.8))
    fig.suptitle("Аналитика: полная сводка (%d волн x %d прогонов)"%(len(W),len(flat)//max(1,len(W))),fontsize=14)
    fig.tight_layout(); savefig(fig,out,"14_dashboard.png")

    # ====================================================================
    # 15. SNAPSHOT COMPARISON (if multiple)
    # ====================================================================
    snaps=sorted(set(r["snapshot_id"] for r in flat))
    if len(snaps)>1 and snaps!=["all"]:
        fig,axes=plt.subplots(2,2,figsize=(16,10))
        for sid in snaps:
            rs=[r for r in flat if r["snapshot_id"]==sid]; sw=sorted(set(r["wave_number"] for r in rs))
            lbl=sid.replace("run_","")[:20]
            axes[0,0].plot(sw,[100*np.mean([r["success"] for r in rs if r["wave_number"]==w]) for w in sw],"o-",ms=3,label=lbl)
            axes[0,1].plot(sw,[np.mean([r["hp_lost"] for r in rs if r["wave_number"]==w]) for w in sw],"o-",ms=3,label=lbl)
        axes[0,0].set_title("Успех (%)"); axes[0,0].legend(fontsize=6); axes[0,0].grid(True,alpha=0.3)
        axes[0,1].set_title("HP потери"); axes[0,1].legend(fontsize=6); axes[0,1].grid(True,alpha=0.3)
        ax=axes[1,0]; ss=[100*np.mean([r["success"] for r in flat if r["snapshot_id"]==s]) for s in snaps]
        ax.bar(range(len(snaps)),ss,color=["#2ecc71" if s>50 else "#e74c3c" for s in ss])
        ax.set_xticks(range(len(snaps))); ax.set_xticklabels([s[:18] for s in snaps],rotation=30,ha="right",fontsize=6)
        ax.set_title("Общий успех"); ax.set_ylim(0,105); ax.grid(True,alpha=0.3,axis="y")
        axes[1,1].axis("off")
        txt="--- СРАВНЕНИЕ ---\n"
        for sid in snaps:
            rs=[r for r in flat if r["snapshot_id"]==sid]
            txt+="%s: %d runs, %.0f%% suc, HP-%.1f\n"%(sid[:25],len(rs),100*np.mean([r["success"] for r in rs]),np.mean([r["hp_lost"] for r in rs]))
        axes[1,1].text(0.02,0.98,txt,transform=axes[1,1].transAxes,fontsize=8,va="top",family="monospace")
        fig.suptitle("Сравнение снепшотов",fontsize=13); fig.tight_layout(); savefig(fig,out,"15_snapshot_comparison.png")

    # ====================================================================
    # CONSOLE REPORT
    # ====================================================================
    print("\n"+"="*95)
    print("FORMULA SILY VRAGA (Power Score)")
    print("="*95)
    print("%-18s %5s %6s %6s %6s %7s %6s %6s %5s %5s  %s"%("Enemy","Power","Fail%","Kill%","HP-","Suc.d","Ore","Dur","Spd","Reg","Abilities"))
    print("-"*95)
    for eid in srt:
        s=es[eid]; print("%-18s %5.0f %5.0f%% %5.0f%% %6.1f %+6.2f %6.1f %5.0fs %5d %5.1f  %s"%(en(eid),pw[eid],s["fail_pct"],s["kill_pct"],s["m_hp_lost"],s["m_suc_d"],s["m_ore"],s["m_dur"],s["base_spd"],s["regen"],s["abilities"] or "-"))

    print("\n"+"="*95)
    print("SLOZHNOST VOLN (Wave Difficulty)")
    print("="*95)
    print("%-5s %7s %7s %7s %7s %7s %6s  %s"%("Wave","Suc%","HP-","Suc.d","Ore","Dur","Regen","Enemies"))
    print("-"*95)
    for wn in sorted(W,key=lambda w:wa[w]["suc_pct"]):
        w=wa[wn]; print("%-5d %6.0f%% %7.1f %+6.2f %7.1f %5.0fs %6.1f  %s"%(wn,w["suc_pct"],w["m_hp_lost"],w["m_suc_d"],w["m_ore"],w["m_dur"],w["m_regen"],", ".join(en(e) for e in w["enemies"])))

    if ab_s:
        print("\n"+"="*95)
        print("VLIYANIE SPOSOBNOSTEY (Ability Impact)")
        print("="*95)
        print("%-20s %6s %7s %7s %7s %10s"%("Ability","Runs","Fail%","HP-","Suc.d","W/o it%"))
        print("-"*95)
        for ab in sorted(ab_s.keys(),key=lambda a:ab_s[a]["fail_pct"],reverse=True):
            a=ab_s[ab]; print("%-20s %6d %6.0f%% %7.1f %+6.2f %9.0f%%"%(ab,a["n"],a["fail_pct"],a["m_hp_lost"],a["m_suc_d"],a["no_ab_fail"]))

    if 'coeffs_f' in dir():
        print("\n"+"="*95)
        print("BALANCE FORMULA (Linear Regression)")
        print("="*95)
        print("Fail%% = "+" + ".join(["%.6f * %s"%(c,n) for c,n in zip(coeffs_f,names_x)]))
        print("HP_lost = "+" + ".join(["%.6f * %s"%(c,n) for c,n in zip(coeffs_h,names_x)]))
        print("\nResiduals (fail%%, top deviations):")
        for i in np.argsort(np.abs(resid_f))[::-1][:5]:
            print("  %s: predicted %.0f%%, actual %.0f%%, residual %+.0f%%"%(labels[i],pred_f[i],Y_fail[i],resid_f[i]))

    print("\nDone. Plots in %s"%out)

if __name__=="__main__": main()
