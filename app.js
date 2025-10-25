// frontend/app.js (Final SMS Checker)

document.addEventListener('DOMContentLoaded', (event) => {
    
    const API_ENDPOINT = "https://ehc13ys186.execute-api.ap-south-1.amazonaws.com/prod/check";

    const checkResultElement = document.getElementById('checkResult');
    const nameInput = document.getElementById('nameInput');
    const phoneInput = document.getElementById('phoneInput'); // NEW INPUT FIELD
    const passwordInput = document.getElementById('checkPassword');

    async function handlePasswordCheck() {
        const name = nameInput.value;
        const phone = phoneInput.value;
        const password = passwordInput.value;
        
        if (!name || !phone || !password) {
            checkResultElement.innerText = '⚠️ Please fill in all fields.';
            checkResultElement.style.color = 'orange';
            return;
        }
        
        checkResultElement.innerText = 'Checking integrity... Please wait...';
        checkResultElement.style.color = '#2c3e50';

        try {
            // Using the native fetch API
            const response = await fetch(API_ENDPOINT, {
                method: 'POST',
                headers: { 'Content-Type': 'application/json' },
                // SENDING 'phone' INSTEAD OF 'email'
                body: JSON.stringify({ name: name, phone: phone, password: password }) 
            });

            const data = await response.json();
            
            if (!response.ok) {
                checkResultElement.innerText = `⚠️ API Error: ${data.message || 'Unknown error'}`;
                checkResultElement.style.color = 'red';
                return;
            }

            if (data.breach_count > 0) {
                checkResultElement.innerHTML = `⚠️ **BREACHED!** Found in **${data.breach_count}** breaches. **Check your SMS for full details.**`;
                checkResultElement.style.color = 'red';
            } else {
                checkResultElement.innerText = '✅ SAFE! This password was not found in known breaches. Check your SMS for confirmation.';
                checkResultElement.style.color = 'green';
            }
            
        } catch (error) {
            checkResultElement.innerText = `❌ Network Error: Could not connect to the server.`;
            checkResultElement.style.color = 'red';
            console.error('Fetch Error:', error);
        }
    }

    window.handlePasswordCheck = handlePasswordCheck;
});