import React from 'react';
import Chart from 'react-apexcharts';
import { BiTrendingUp, BiTrendingDown, BiGroup, BiStore, BiCalendarEvent, BiDollarCircle } from 'react-icons/bi';
import { useThemeMode } from '../context/ThemeContext';

export const Analytics: React.FC = () => {
    const { mode } = useThemeMode();
    const isDark = mode === 'dark';
    const textColor = isDark ? '#8c9097' : '#6c757d';
    const gridColor = isDark ? 'rgba(255,255,255,0.06)' : '#e9edf4';

    const kpis = [
        { label: 'Total Revenue', value: '₹24.8L', trend: 18.2, icon: <BiDollarCircle />, cls: 'success' },
        { label: 'Total Bookings', value: '3,241', trend: 12.5, icon: <BiCalendarEvent />, cls: 'primary' },
        { label: 'Active Users', value: '1,847', trend: 8.3, icon: <BiGroup />, cls: 'info' },
        { label: 'Venue Partners', value: '156', trend: -2.1, icon: <BiStore />, cls: 'warning' },
    ];

    const lineOptions: ApexCharts.ApexOptions = {
        chart: { type: 'line', height: 320, toolbar: { show: false }, fontFamily: "'Space Grotesk', sans-serif", background: 'transparent' },
        colors: ['#845adf', '#26bf94', '#e6533c'],
        stroke: { curve: 'smooth', width: 2.5 },
        xaxis: {
            categories: ['Jan', 'Feb', 'Mar', 'Apr', 'May', 'Jun', 'Jul', 'Aug', 'Sep', 'Oct', 'Nov', 'Dec'],
            labels: { style: { colors: textColor, fontSize: '11px' } },
            axisBorder: { show: false }, axisTicks: { show: false },
        },
        yaxis: { labels: { style: { colors: textColor, fontSize: '11px' } } },
        grid: { borderColor: gridColor, strokeDashArray: 3 },
        legend: { position: 'top', horizontalAlign: 'right', labels: { colors: textColor } },
        tooltip: { theme: isDark ? 'dark' : 'light' },
        dataLabels: { enabled: false },
    };
    const lineSeries = [
        { name: 'Bookings', data: [120, 145, 162, 198, 215, 248, 280, 310, 295, 342, 380, 412] },
        { name: 'Revenue (K)', data: [85, 105, 118, 142, 158, 180, 205, 225, 215, 252, 278, 310] },
        { name: 'Cancellations', data: [8, 12, 10, 15, 18, 14, 22, 20, 16, 25, 19, 28] },
    ];

    const pieOptions: ApexCharts.ApexOptions = {
        chart: { type: 'donut', height: 280, fontFamily: "'Space Grotesk', sans-serif" },
        colors: ['#845adf', '#23b7e5', '#26bf94', '#f5b849', '#e34d8b'],
        labels: ['Clubs', 'Lounges', 'Bars', 'Rooftops', 'Restaurants'],
        legend: { position: 'bottom', labels: { colors: textColor } },
        stroke: { show: false },
        dataLabels: { enabled: false },
        plotOptions: { pie: { donut: { size: '65%', labels: { show: true, name: { color: textColor }, value: { color: isDark ? '#d4d5d9' : '#1a1d21' }, total: { show: true, label: 'Total', color: textColor } } } } },
    };
    const pieSeries = [42, 28, 35, 18, 33];

    const barOptions: ApexCharts.ApexOptions = {
        chart: { type: 'bar', height: 280, toolbar: { show: false }, fontFamily: "'Space Grotesk', sans-serif", background: 'transparent' },
        colors: ['#845adf', '#23b7e5'],
        plotOptions: { bar: { borderRadius: 4, columnWidth: '50%' } },
        xaxis: {
            categories: ['Club Infinity', 'Skybar', 'Velvet Room', 'Grand Terrace', 'Neon District'],
            labels: { style: { colors: textColor, fontSize: '10px' } },
            axisBorder: { show: false }, axisTicks: { show: false },
        },
        yaxis: { labels: { style: { colors: textColor, fontSize: '11px' } } },
        grid: { borderColor: gridColor, strokeDashArray: 3 },
        legend: { position: 'top', horizontalAlign: 'right', labels: { colors: textColor } },
        tooltip: { theme: isDark ? 'dark' : 'light' },
        dataLabels: { enabled: false },
    };
    const barSeries = [
        { name: 'Bookings', data: [89, 76, 64, 52, 48] },
        { name: 'Revenue (K)', data: [120, 95, 82, 68, 55] },
    ];

    return (
        <div>
            {/* KPI Row */}
            <div className="row g-3 mb-4">
                {kpis.map((kpi, i) => (
                    <div className="col-sm-6 col-xl-3" key={kpi.label}>
                        <div className={`stat-card animate-in animate-in-${i + 1}`}>
                            <div style={{ display: 'flex', justifyContent: 'space-between', alignItems: 'flex-start' }}>
                                <div>
                                    <div className="stat-card-label">{kpi.label}</div>
                                    <div className="stat-card-value">{kpi.value}</div>
                                    <div className={`stat-card-trend ${kpi.trend >= 0 ? 'up' : 'down'}`}>
                                        {kpi.trend >= 0 ? <BiTrendingUp /> : <BiTrendingDown />}
                                        <span>{Math.abs(kpi.trend)}%</span>
                                        <span className="trend-text">vs last year</span>
                                    </div>
                                </div>
                                <div className={`stat-card-icon ${kpi.cls}`}>{kpi.icon}</div>
                            </div>
                        </div>
                    </div>
                ))}
            </div>

            {/* Line Chart */}
            <div className="vz-card mb-4 animate-in animate-in-5">
                <div className="vz-card-header">
                    <h6 className="vz-card-title">Performance Overview</h6>
                    <span className="vz-badge primary">12 Months</span>
                </div>
                <div className="vz-card-body">
                    <Chart options={lineOptions} series={lineSeries} type="line" height={320} />
                </div>
            </div>

            {/* Pie + Bar */}
            <div className="row g-3">
                <div className="col-xl-5">
                    <div className="vz-card animate-in animate-in-5">
                        <div className="vz-card-header">
                            <h6 className="vz-card-title">Venue Categories</h6>
                        </div>
                        <div className="vz-card-body">
                            <Chart options={pieOptions} series={pieSeries} type="donut" height={280} />
                        </div>
                    </div>
                </div>
                <div className="col-xl-7">
                    <div className="vz-card animate-in animate-in-6">
                        <div className="vz-card-header">
                            <h6 className="vz-card-title">Revenue by Venue</h6>
                        </div>
                        <div className="vz-card-body">
                            <Chart options={barOptions} series={barSeries} type="bar" height={280} />
                        </div>
                    </div>
                </div>
            </div>
        </div>
    );
};

export default Analytics;
