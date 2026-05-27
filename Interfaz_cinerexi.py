import streamlit as st
import plotly.express as px
import pandas as pd
import mysql.connector
from datetime import datetime

gama_verdes = ["#00441b", "#006d2c", "#238b45", "#41ab5d", "#74c476", "#a1d99b", "#c7e9c0", "#e7f5e1"]


def conectar_db():
    return mysql.connector.connect(
        host="localhost",
        user="root",
        password="Sayury2026.",
        database="CineRex"
    )


st.set_page_config(
    page_title="🎬 Dashboard Cine Rex",
    page_icon="🎬",
    layout="wide",
    initial_sidebar_state="expanded"
)

st.markdown(f"""
<style>
    .main-header {{
        font-size: 3rem;
        color: {gama_verdes[1]};
        text-align: center;
        margin-bottom: 2rem;
        text-shadow: 2px 2px 4px rgba(0,0,0,0.1);
    }}
</style>
""", unsafe_allow_html=True)

st.markdown('<h1 class="main-header">🎬 DASHBOARD CINE REX</h1>', unsafe_allow_html=True)

try:
    conn = conectar_db()

    # Traemos datos de tus Vistas SQL
    df_box_office = pd.read_sql("SELECT * FROM View_Box_Office_Chart", conn)
    df_occupancy = pd.read_sql("SELECT * FROM View_Theater_Occupancy", conn)
    df_revenue = pd.read_sql("SELECT * FROM View_Daily_Revenue", conn)
    df_inventory = pd.read_sql("SELECT * FROM View_Inventory_Alert", conn)

    conn.close()

    st.sidebar.markdown("## 🎛️ PANEL DE CONTROL")
    fecha_seleccionada = st.sidebar.date_input("📅 Fecha:", datetime.now().date())

    lista_peliculas = ['Todas'] + list(df_box_office['movie'].unique())
    pelicula_seleccionada = st.sidebar.selectbox("🎥 Película:", lista_peliculas)

    lista_salas = ['Todas'] + list(df_occupancy['theater'].unique())
    sala_seleccionada = st.sidebar.selectbox("🏛️ Sala:", lista_salas)

    if pelicula_seleccionada != 'Todas':
        df_box_office = df_box_office[df_box_office['movie'] == pelicula_seleccionada]
        df_occupancy = df_occupancy[df_occupancy['movie'] == pelicula_seleccionada]

    if sala_seleccionada != 'Todas':
        df_occupancy = df_occupancy[df_occupancy['theater'] == sala_seleccionada]

    col1, col2, col3, col4 = st.columns(4)
    with col1:
        st.metric("Ventas Totales", f"${df_box_office['total_revenue'].sum():,.2f}")
    with col2:
        st.metric("Tickets Vendidos", int(df_box_office['tickets_sold'].sum()))
    with col3:
        st.metric("Ocupación Promedio", f"{df_occupancy['occupancy_pct'].mean():.1f}%")
    with col4:
        st.metric("Alertas Stock", len(df_inventory))

    st.divider()


    col_izq, col_der = st.columns(2)

    with col_izq:
        st.subheader("📈 Ingresos por Fuente (Tickets vs Dulcería)")
        fig_rev = px.bar(df_revenue, x='sale_date', y='revenue', color='source',
                         color_discrete_sequence=[gama_verdes[2], gama_verdes[4]],
                         barmode='group', template="plotly_white")
        st.plotly_chart(fig_rev, use_container_width=True)

    with col_der:
        st.subheader("🎥 Top Taquilla")
        fig_box = px.bar(df_box_office, x='movie', y='total_revenue',
                         color='total_revenue', color_continuous_scale=gama_verdes)
        fig_box.update_layout(coloraxis_showscale=False)
        st.plotly_chart(fig_box, use_container_width=True)


    st.subheader("🏛️ Ocupación Detallada de Funciones")
    st.dataframe(df_occupancy, use_container_width=True, hide_index=True)


    if not df_inventory.empty:
        with st.expander("⚠️ ALERTAS DE INVENTARIO CRÍTICO"):
            st.table(df_inventory)

except Exception as e:
    st.error(f"❌ Error al conectar con MySQL: {e}")
    st.info("Verifica que el servicio de MySQL esté activo y que tu usuario/contraseña sean correctos.")