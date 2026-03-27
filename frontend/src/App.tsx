import { BrowserRouter, Routes, Route } from 'react-router-dom'

function App() {
  return (
    <BrowserRouter>
      <Routes>
        <Route path="/" element={<div className="p-8 text-2xl font-bold">Personal Finance App</div>} />
      </Routes>
    </BrowserRouter>
  )
}

export default App
