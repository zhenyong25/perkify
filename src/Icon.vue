<script setup>
import { ArrowUpRight, ArrowDownLeft, ArrowRight, Plus, Search, LayoutDashboard, Wallet, Ticket, Gem, Clock3, Settings, ChevronRight, ChevronDown, X, Gift, Sparkles, Bell, CreditCard, Check, Coffee, Plane, ShoppingBag, Copy, Trash2, Pencil, Download, Upload, Menu, CircleHelp, CheckCheck, Stamp } from 'lucide-vue-next'
defineProps({ name: String, size: { type: [Number, String], default: 20 } })
const icons = { ArrowUpRight, ArrowDownLeft, ArrowRight, Plus, Search, LayoutDashboard, Wallet, Ticket, Gem, Clock3, Settings, ChevronRight, ChevronDown, X, Gift, Sparkles, Bell, CreditCard, Check, Coffee, Plane, ShoppingBag, Copy, Trash2, Pencil, Download, Upload, Menu, CircleHelp, CheckCheck, Stamp }
</script>
<template><component :is="icons[name] || icons.Gift" :size="size" :stroke-width="1.7" aria-hidden="true" /></template>
